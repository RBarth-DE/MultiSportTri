//! MultiSportTri - continuous triathlon recording (swim / bike / run)
//! with manual phase changes, written for the Garmin Venu 3.
//!
//! This file holds the application class, the activity recording session,
//! the phase state machine, sensor handling and the FIT developer fields.
//!
//! Key design decisions:
//!  * One single ActivityRecording session (sport = triathlon) stays open
//!    for the whole exercise (requirement 1).
//!  * Phase changes happen on an explicit button press only, never via
//!    touch. While the recording is running the device's native recording
//!    engine consumes the Start/Stop and Back/Lap buttons and reports them
//!    through the session timer events (TIMER_EVENT_*). A lap press during
//!    a multisport recording fires TIMER_EVENT_NEXT_MULTISPORT_LEG; the
//!    ordinary TIMER_EVENT_LAP is handled as a fallback.
//!  * The public Connect IQ API has no "setSubSport" method, so per-leg
//!    sub-sports cannot be written into the FIT file by the app. Instead
//!    every phase is labeled with two FIT developer fields (one per record
//!    message, one per lap message), which makes the three legs clearly
//!    distinguishable in Garmin Connect.
//!  * Swim detection (stroke counting) is not exposed to apps either, so
//!    the swim leg is recorded time- and GPS-distance-based.
//!  * A bike cadence sensor (ANT+ or BLE, paired in the watch settings) is
//!    enabled only during the bike phase.

import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.FitContributor;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

//! Selectable data field types (values of the settings lists).
enum {
    FIELD_NONE = 0,
    FIELD_HR = 1,
    FIELD_CADENCE = 2,
    FIELD_DISTANCE = 3,
    FIELD_TIME = 4,
    FIELD_PACE = 5,
    FIELD_SPEED = 6,
    //! internal only, not selectable in the settings
    FIELD_TOTAL_DISTANCE = 7,
    //! CGM glucose (AAPS Garmin plugin)
    FIELD_CGM = 8
}

//! Exercise phases, in order. The same values are written into the FIT
//! developer fields so Garmin Connect can show the legs.
enum {
    PHASE_SWIM = 1,
    PHASE_T1 = 2,
    PHASE_BIKE = 3,
    PHASE_T2 = 4,
    PHASE_RUN = 5
}

//! UI / recording state.
enum {
    STATE_READY = 0,
    STATE_RUNNING = 1,
    STATE_PAUSED = 2,
    STATE_STOPPED = 3,
    STATE_SAVED = 4
}

//! Fixed phase sequence: swim -> T1 -> bike -> T2 -> run (terminal).
//! Held as an instance field: a module-level const with a cast would run
//! executable code during module initialization, before onStart ever
//! executes, which has caused load-time crashes on some device runtimes.

//! FIT developer field ids (must match resources/resources.xml).
const FIT_FIELD_RECORD_ID = 0;
const FIT_FIELD_LAP_ID = 1;
const FIT_FIELD_GLUCOSE_ID = 2;
const FIT_FIELD_CADENCE_ID = 3;

//! Storage keys for state that survives an app exit mid-exercise.
const STORAGE_PHASE = "mstPhase";
const STORAGE_PHASE_INDEX = "mstPhaseIndex";
const STORAGE_STATE = "mstState";

//! LAP gesture: quiet gap that ends a button gesture, and the repeat
//! count that means "long press" on the Venu 3. The long-press stream
//! repeats about every 400 ms, so the gap must be longer than that.
const LAP_GESTURE_GAP_MS = 650;
const LAP_LONG_PRESS_COUNT = 3;

class MultiSportTriApp extends Application.AppBase {

    //! The single activity recording session (created at app start,
    //! kept open until the activity is saved or discarded).
    private var _session as ActivityRecording.Session or Null = null;

    private var _state as Number = STATE_READY;
    private var _phase as Number = PHASE_SWIM;
    private var _phaseIndex as Number = 0;

    //! Cached activity info, refreshed once per second.
    private var _timerTime as Number = 0;               // ms
    private var _elapsedDistance as Float = 0.0;        // m, whole session
    private var _heartRate as Number or Null = null;
    private var _infoSpeed as Float or Null = null;     // m/s
    private var _nativeCadence as Number or Null = null;

    //! Per-leg tracking (reset on every phase entry).
    private var _legDistance as Float = 0.0;            // m, current phase
    private var _lastPosition as Position.Location or Null = null;
    private var _gpsQuality as Number = Position.QUALITY_NOT_AVAILABLE;
    private var _gpsSpeed as Float or Null = null;      // m/s

    //! Cadence sensor (bike phase only).
    private var _cadence as Number or Null = null;
    private var _cadenceConnected as Boolean = false;

    //! FIT developer fields.
    private var _fitPhaseRecord as FitContributor.Field or Null = null;
    private var _fitPhaseLap as FitContributor.Field or Null = null;
    private var _fitGlucose as FitContributor.Field or Null = null;
    private var _fitCadence as FitContributor.Field or Null = null;

    //! Per-second UI refresh timer.
    private var _uiTimer as Timer.Timer or Null = null;

    //! Configured data fields per phase (4 entries each).
    private var _swimFields as Array<Number> or Null = null;
    private var _bikeFields as Array<Number> or Null = null;
    private var _runFields as Array<Number> or Null = null;

    //! True when the gesture that just ended was a long press. Key 7
    //! arrives AFTER the quiet-gap timer has already finished the
    //! gesture, so the delegate has to ask this flag to decide whether
    //! to hand key 7 to the system (native stop menu).
    private var _lastGestureWasLong as Boolean = false;
    //! True while advancePhase runs, so a TIMER_EVENT_LAP caused by our
    //! own addLap() cannot re-enter and skip the transition.
    private var _inAdvance as Boolean = false;
    //! Number of self-inflicted lap timer events still to swallow
    //! (addLap() reports TIMER_EVENT_LAP / NEXT_MULTISPORT_LEG back).
    private var _selfLapEvents as Number = 0;

    //! True once the deferred heavyweight initialization has run.
    private var _initDone as Boolean = false;

    //! LAP/Back gesture tracking. On the Venu 3 the button arrives as a
    //! stream of onBack() behaviors (no KEY_LAP / key 5), and a long press
    //! is a slow repeat stream (~400 ms) that ends with key 7. Each event
    //! must NOT advance the phase — exactly one advance per short press,
    //! zero for a long press (which only opens the stop menu).
    private var _lapKeyCount as Number = 0;
    //! One-shot timer that ends the current LAP gesture after a quiet gap.
    private var _advanceTimer as Timer.Timer or Null = null;

    //! UI tick counter (CGM refresh every 180 s).
    private var _tickCount as Number = 0;

    //! Last glucose value written to the FIT (change detection).
    private var _lastFitGlucose as Number = -1;

    //! Fixed phase order (instance copy, see module-level comment above).
    private var _phaseOrder as Array<Number> =
        [PHASE_SWIM, PHASE_T1, PHASE_BIKE, PHASE_T2, PHASE_RUN] as Array<Number>;

    function initialize() {
        AppBase.initialize();
    }

    //! Called when the app is launched.
    //! @param state Startup state
    function onStart(state as Dictionary or Null) as Void {
        initCore();
        showUi();
    }

    //! Initialization that runs at every launch, independent of the UI
    //! entry style (watch-app vs widget).
    function initCore() as Void {
        loadSettings();

        // Per-second refresh of the activity data and the FIT phase field.
        // The first tick also runs the heavyweight initialization (session,
        // state restore, sensors): it is deliberately deferred out of
        // onStart, because fatal device errors in those native calls would
        // crash the app before the UI ever appears.
        _uiTimer = new Timer.Timer();
        _uiTimer.start(method(:onUiTick), 1000, true);

        // Initial CGM fetch; refreshed every 3 minutes via onUiTick.
        glucose.fetch();

        WatchUi.requestUpdate();
    }

    //! Show the main UI (watch-app entry style; the widget entry uses
    //! getInitialView() instead and skips this).
    function showUi() as Void {
        var view = new MultiSportTriView(self);
        WatchUi.pushView(view, new MultiSportTriDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }

    //! Deferred heavyweight initialization, run on the first timer tick.
    //! Creates (or re-attaches to) the recording session and restores the
    //! exercise state across app restarts.
    function heavyInit() as Void {
        _initDone = true;

        // Create (or re-attach to) the single recording session.
        _session = getOrCreateSession();
        attachTimerListener();
        setupFitFields();

        // Restore the exercise state across app restarts.
        restoreStateFromStorage();
        if (_session != null && _session.isRecording()) {
            // The user left the app while the recording was still running.
            _state = STATE_RUNNING;
            setPhaseEnvironment(_phase);
            enableGps();
        } else if (_state != STATE_STOPPED) {
            _state = STATE_READY;
            _phase = PHASE_SWIM;
            _phaseIndex = 0;
            _legDistance = 0.0;
            _lastPosition = null;
        }
        // GPS from the very beginning, so a fix is ready when the
        // recording starts and the READY screen can show the status.
        enableGps();
        WatchUi.requestUpdate();
    }

    //! Called when the app exits. The recording is deliberately NOT
    //! stopped here: the native recording engine keeps it alive, so a
    //! short accidental exit mid-race does not lose the activity.
    //! @param state Stopped state
    function onStop(state as Dictionary or Null) as Void {
        cancelPendingAdvance();
        if (_uiTimer != null) {
            _uiTimer.stop();
            _uiTimer = null;
        }
        disableCadenceSensor();
        if (Toybox has :Sensor) {
            try {
                Sensor.enableSensorEvents(null);
            } catch (e) {
            }
        }
        disableGps();
        persistState();
    }

    //! Called when the user changes settings in Garmin Connect Mobile.
    function onSettingsChanged() as Void {
        loadSettings();
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Session management
    // ------------------------------------------------------------------

    //! Create the single recording session (or return the existing one if
    //! a previous session was never saved or discarded).
    //! @return The session object, or null if recording is unsupported
    function getOrCreateSession() as ActivityRecording.Session or Null {
        if (!(Toybox has :ActivityRecording)) {
            return null;
        }
        try {
            // The Venu 3 API exposes SPORT_MULTISPORT (the multisport
            // container sport) plus SUB_SPORT_TRIATHLON, but not the
            // SPORT_TRIATHLON alias; the combination below makes Garmin
            // Connect present the activity as a triathlon.
            return ActivityRecording.createSession({
                :name => "MultiSportTri",
                :sport => Activity.SPORT_MULTISPORT,
                :subSport => Activity.SUB_SPORT_TRIATHLON
            });
        } catch (e) {
            return null;
        }
    }

    //! Register the session timer-event callback. Without this the
    //! native engine never reports LAP / NEXT_MULTISPORT_LEG and the
    //! phase cannot change while the recording owns the buttons.
    function attachTimerListener() as Void {
        if (_session == null) {
            return;
        }
        try {
            _session.setTimerEventListener(method(:onTimerEvent));
        } catch (e) {
        }
    }

    //! Start (or resume) the recording.
    //! @return true if the recording is now running
    function startRecording() as Boolean {
        if (_session == null) {
            _session = getOrCreateSession();
            if (_session != null) {
                attachTimerListener();
                setupFitFields();
            }
        }
        if (_session == null || _session.isRecording()) {
            return false;
        }
        var isResume = (_state == STATE_STOPPED || _state == STATE_PAUSED);
        var ok = false;
        try {
            ok = _session.start();
        } catch (e) {
        }
        if (!ok) {
            return false;
        }
        if (!isResume) {
            // Fresh activity: always begin with the swim leg.
            _phase = PHASE_SWIM;
            _phaseIndex = 0;
            _legDistance = 0.0;
            _lastPosition = null;
        }
        _state = STATE_RUNNING;
        setPhaseEnvironment(_phase);
        enableGps();
        persistState();
        WatchUi.requestUpdate();
        return true;
    }

    //! Resume a stopped/paused recording in place.
    //! @return true if the recording is now running
    function resumeRecording() as Boolean {
        return startRecording();
    }

    //! Stop (pause) the recording without saving.
    //! @return true if the recording is now stopped
    function stopRecording() as Boolean {
        var ok = false;
        try {
            if (_session != null) {
                ok = _session.stop();
            }
        } catch (e) {
        }
        if (ok) {
            _state = STATE_STOPPED;
            disableGps();
            persistState();
            WatchUi.requestUpdate();
        }
        return ok;
    }

    //! Stop the recording and save the FIT file.
    //! @return true if the session was saved
    function saveSession() as Boolean {
        var ok = false;
        try {
            if (_session != null) {
                _session.stop();
                ok = _session.save();
            }
        } catch (e) {
        }
        _session = null;
        _fitPhaseRecord = null;
        _fitPhaseLap = null;
        _fitGlucose = null;
        _fitCadence = null;
        _state = STATE_SAVED;
        disableCadenceSensor();
        disableGps();
        persistState();
        WatchUi.requestUpdate();
        return ok;
    }

    //! Stop the recording and discard the data.
    //! @return true if the session was discarded
    function discardSession() as Boolean {
        var ok = false;
        try {
            if (_session != null) {
                _session.stop();
                ok = _session.discard();
            }
        } catch (e) {
        }
        _session = null;
        _fitPhaseRecord = null;
        _fitPhaseLap = null;
        _fitGlucose = null;
        _fitCadence = null;
        _state = STATE_READY;
        _phase = PHASE_SWIM;
        _phaseIndex = 0;
        _legDistance = 0.0;
        _lastPosition = null;
        disableCadenceSensor();
        disableGps();
        persistState();
        WatchUi.requestUpdate();
        return ok;
    }

    //! Reset the app for a new activity.
    function resetToReady() as Void {
        _state = STATE_READY;
        _phase = PHASE_SWIM;
        _phaseIndex = 0;
        _legDistance = 0.0;
        _lastPosition = null;
        _timerTime = 0;
        _elapsedDistance = 0.0;
        disableCadenceSensor();
        disableGps();
        persistState();
        WatchUi.requestUpdate();
    }

    //! Whether the recording is currently active.
    //! @return true while recording
    function isRecording() as Boolean {
        return (_session != null) && _session.isRecording();
    }

    // ------------------------------------------------------------------
    // Timer events (native recording engine)
    // ------------------------------------------------------------------

    //! Receives all timer events from the recording session. While the
    //! recording is active, the system consumes the device buttons and
    //! reports them here.
    //! @param eventType A TIMER_EVENT_* value
    //! @param eventData Event payload
    function onTimerEvent(eventType as ActivityRecording.TimerEventType, eventData as Dictionary) as Void {
        try {
            // Compare against the raw values too: a multisport session
            // reports the LAP button as NEXT_MULTISPORT_LEG (7).
            if (eventType == ActivityRecording.TIMER_EVENT_START || eventType == 0) {
                var wasFresh = (_state == STATE_READY || _state == STATE_SAVED);
                if (wasFresh) {
                    _phase = PHASE_SWIM;
                    _phaseIndex = 0;
                    _legDistance = 0.0;
                    _lastPosition = null;
                }
                _state = STATE_RUNNING;
                setPhaseEnvironment(_phase);
                enableGps();
            } else if (eventType == ActivityRecording.TIMER_EVENT_STOP || eventType == 1) {
                // Stopping only pauses the recording; it can be resumed
                // and is finalized with save() or discard().
                _state = STATE_STOPPED;
                disableGps();
            } else if (eventType == ActivityRecording.TIMER_EVENT_PAUSE || eventType == 2) {
                _state = STATE_PAUSED;
                disableGps();
            } else if (eventType == ActivityRecording.TIMER_EVENT_RESUME || eventType == 3) {
                _state = STATE_RUNNING;
                setPhaseEnvironment(_phase);
                enableGps();
            } else if (eventType == ActivityRecording.TIMER_EVENT_LAP || eventType == 4 ||
                       eventType == ActivityRecording.TIMER_EVENT_NEXT_MULTISPORT_LEG || eventType == 7) {
                // On the Venu 3 these never come from the LAP button (the
                // onBack gesture does the phase change). They DO come back
                // from our own addLap() — swallow those, otherwise one
                // press advances twice and skips T1/T2.
                if (_selfLapEvents > 0) {
                    _selfLapEvents = _selfLapEvents - 1;
                }
            } else if (eventType == ActivityRecording.TIMER_EVENT_RESET || eventType == 5) {
                resetToReady();
            }
            // TIMER_EVENT_WORKOUT_STEP_COMPLETE is intentionally ignored.
        } catch (e) {
        }
        persistState();
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Phase state machine
    // ------------------------------------------------------------------

    //! Record one LAP/Back event and (re)start the gesture-end timer.
    //! The phase advances only once the whole gesture is over, so the
    //! slow long-press repeat stream cannot walk through every phase.
    function requestPhaseAdvance() as Void {
        _lapKeyCount = _lapKeyCount + 1;
        if (_advanceTimer != null) {
            _advanceTimer.stop();
            _advanceTimer = null;
        }
        _advanceTimer = new Timer.Timer();
        _advanceTimer.start(method(:endLapGesture), LAP_GESTURE_GAP_MS, false);
    }

    //! Cancel a pending deferred phase advance (long press detected).
    function cancelPendingAdvance() as Void {
        if (_advanceTimer != null) {
            _advanceTimer.stop();
            _advanceTimer = null;
        }
    }

    //! Quiet gap after the last LAP/Back event: the gesture is over.
    function endLapGesture() as Void {
        _advanceTimer = null;
        finishLapGesture(false);
    }

    //! Finish a LAP/Back gesture. A short press advances once; a long
    //! press (repeat stream, and/or the key-7 marker) does not — it only
    //! opens the native stop menu.
    //! @param fromKey7 true when the key-7 long-press marker ended it
    function finishLapGesture(fromKey7 as Boolean) as Void {
        cancelPendingAdvance();
        var count = _lapKeyCount;
        _lapKeyCount = 0;
        if (count == 0) {
            // Late key 7 after the quiet gap already ended the gesture.
            return;
        }
        if (count >= LAP_LONG_PRESS_COUNT) {
            // Long press: native stop menu only, never a phase change.
            _lastGestureWasLong = true;
            return;
        }
        _lastGestureWasLong = false;
        advancePhase();
    }

    //! True while a long-press repeat stream is in progress.
    function isLongPressGesture() as Boolean {
        return _lapKeyCount >= LAP_LONG_PRESS_COUNT;
    }

    //! True if the gesture that just ended was a long press (used for
    //! the late key-7 marker).
    function wasLastGestureLong() as Boolean {
        return _lastGestureWasLong;
    }

    //! Advance to the next phase (swim -> T1 -> bike -> T2 -> run).
    //! Called from the timer events and, as a fallback, from the input
    //! delegate when the system hands the Back key to the app.
    function advancePhase() as Void {
        if (_inAdvance) {
            return;
        }
        if (_state != STATE_RUNNING && _state != STATE_PAUSED) {
            return;
        }
        _inAdvance = true;
        // No getTimer() debounce: System.getTimer() returns a near-zero
        // value on the Venu 3 (FW 17.05), so `now - last < 150` rejected
        // every advance. The LAP gesture already coalesces one physical
        // press into exactly one call.

        var previousPhase = _phase;
        if (_phaseIndex < _phaseOrder.size() - 1) {
            _phaseIndex = _phaseIndex + 1;
        }
        // Run is terminal: further presses stay on the run leg.
        _phase = _phaseOrder[_phaseIndex];

        if (_phase != previousPhase) {
            // Close the old lap first (its FIT lap message carries the
            // old phase label), then enter the new phase.
            markLapBoundary();
            onPhaseEnter(_phase);
        }
        // A redundant press on the terminal phase still laps the
        // recording (done by the system) but must not reset the leg.

        // Feedback, especially helpful while swimming.
        try {
            Attention.playTone(Attention.TONE_SUCCESS);
            Attention.vibrate([new Attention.VibeProfile(100, 150)]);
        } catch (e) {
        }
        persistState();
        WatchUi.requestUpdate();
        _inAdvance = false;
    }

    //! Full phase entry: reset the per-leg metrics, label the new lap and
    //! adjust the sensors.
    //! @param phase The new phase
    function onPhaseEnter(phase as Number) as Void {
        _legDistance = 0.0;
        _lastPosition = null;
        setPhaseEnvironment(phase);
    }

    //! Write a lap marker into the FIT file via the public addLap() API.
    //! The recording continues without interruption; the lap message
    //! carries the lap-level phase label that was set at phase entry.
    function markLapBoundary() as Void {
        if (_session == null || !_session.isRecording()) {
            return;
        }
        try {
            // addLap() reports a TIMER_EVENT_LAP / NEXT_MULTISPORT_LEG
            // back at us; ignore that echo or the phase advances twice.
            _selfLapEvents = _selfLapEvents + 1;
            _session.addLap();
        } catch (e) {
            _selfLapEvents = 0;
        }
    }

    //! Set the FIT lap label for the phase and enable/disable the cadence
    //! sensor. The lap-level field value is set on phase ENTRY so that the
    //! lap message written when the phase ends carries the right label.
    //! @param phase The current phase
    function setPhaseEnvironment(phase as Number) as Void {
        if (_fitPhaseLap != null) {
            try {
                _fitPhaseLap.setData(phase);
            } catch (e) {
            }
        }
        if (phase == PHASE_BIKE) {
            enableCadenceSensor();
        } else {
            disableCadenceSensor();
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Sensors (bike cadence) and GPS
    // ------------------------------------------------------------------

    //! Connect to a paired bike cadence sensor (ANT+ or BLE). The sensor
    //! itself is paired through the watch's own sensor settings; the app
    //! enables the sensor type and receives 1 Hz Sensor.Info updates.
    function enableCadenceSensor() as Void {
        _cadence = null;
        _cadenceConnected = false;
        if (!(Toybox has :Sensor)) {
            return;
        }
        try {
            Sensor.enableSensorEvents(method(:onSensorInfo));
        } catch (e) {
        }
        try {
            Sensor.setEnabledSensors([Sensor.SENSOR_BIKECADENCE] as Array<Sensor.SensorType>);
        } catch (e) {
        }
        WatchUi.requestUpdate();
    }

    //! Disable the cadence sensor when leaving the bike phase.
    function disableCadenceSensor() as Void {
        _cadence = null;
        _cadenceConnected = false;
        if (!(Toybox has :Sensor)) {
            return;
        }
        try {
            Sensor.setEnabledSensors(new Array<Sensor.SensorType>[0]);
        } catch (e) {
        }
    }

    //! Enable continuous GPS for distance tracking. Only used while a
    //! recording is active (open-water swim and per-leg distance).
    function enableGps() as Void {
        try {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        } catch (e) {
        }
    }

    //! Disable GPS when it is no longer needed.
    function disableGps() as Void {
        try {
            Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        } catch (e) {
        }
    }

    //! 1 Hz sensor information callback (cadence while the bike sensor
    //! is enabled).
    //! @param info Current Sensor.Info
    function onSensorInfo(info as Sensor.Info) as Void {
        if (info.cadence != null) {
            _cadence = info.cadence;
            _cadenceConnected = true;
            WatchUi.requestUpdate();
        }
    }

    //! Continuous GPS position callback; accumulates the current leg's
    //! distance from consecutive good fixes.
    //! @param info Current Position.Info
    function onPosition(info as Position.Info) as Void {
        _gpsQuality = info.accuracy;
        if (info.accuracy >= Position.QUALITY_GOOD && info.position != null) {
            var position = info.position;
            var last = _lastPosition;
            if (last != null) {
                var step = distanceBetween(last, position);
                if (step < 100.0) {
                    // Reject implausible jumps (GPS glitches).
                    _legDistance = _legDistance + step;
                }
            }
            _lastPosition = position;
        }
        if (info.accuracy >= Position.QUALITY_GOOD && info.speed != null) {
            _gpsSpeed = info.speed;
        }
        WatchUi.requestUpdate();
    }

    //! Great-circle distance between two locations in meters.
    //! @param a First location
    //! @param b Second location
    //! @return Distance in meters
    function distanceBetween(a as Position.Location, b as Position.Location) as Float {
        var aDeg = a.toDegrees();
        var bDeg = b.toDegrees();
        var lat1 = aDeg[0] * (Math.PI / 180.0);
        var lon1 = aDeg[1] * (Math.PI / 180.0);
        var lat2 = bDeg[0] * (Math.PI / 180.0);
        var lon2 = bDeg[1] * (Math.PI / 180.0);
        var dLat = lat2 - lat1;
        var dLon = lon2 - lon1;
        var sinLat = Math.sin(dLat / 2.0);
        var sinLon = Math.sin(dLon / 2.0);
        var h = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLon * sinLon;
        if (h > 1.0) {
            h = 1.0;
        }
        return 2.0 * 6371000.0 * Math.asin(Math.sqrt(h));
    }

    // ------------------------------------------------------------------
    // FIT developer fields
    // ------------------------------------------------------------------

    //! Create the two FIT developer fields (per-record chart + per-lap
    //! table). Field ids must match resources/resources.xml.
    function setupFitFields() as Void {
        if (_session == null || !(Toybox has :FitContributor)) {
            return;
        }
        try {
            _fitPhaseRecord = _session.createField(
                "mst_phase", FIT_FIELD_RECORD_ID, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "-"});
            _fitPhaseLap = _session.createField(
                "mst_phase_lap", FIT_FIELD_LAP_ID, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_LAP, :units => "-"});
            _fitGlucose = _session.createField(
                "mst_glucose", FIT_FIELD_GLUCOSE_ID, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg/dl"});
            _fitCadence = _session.createField(
                "mst_cadence", FIT_FIELD_CADENCE_ID, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm"});
        } catch (e) {
            _fitPhaseRecord = null;
            _fitPhaseLap = null;
            _fitGlucose = null;
            _fitCadence = null;
        }
    }

    // ------------------------------------------------------------------
    // 1 Hz refresh
    // ------------------------------------------------------------------

    //! Per-second tick: cache the activity info and write the phase into
    //! the per-record FIT developer field. The very first tick also runs
    //! the deferred heavyweight initialization.
    function onUiTick() as Void {
        if (!_initDone) {
            heavyInit();
        }
        _tickCount = _tickCount + 1;
        if (_tickCount % 180 == 0) {
            glucose.fetch();
        }
        var info = Activity.getActivityInfo();
        if (info != null) {
            if (info.timerTime != null) {
                _timerTime = info.timerTime;
            }
            if (info.elapsedDistance != null) {
                _elapsedDistance = info.elapsedDistance;
            }
            _heartRate = info.currentHeartRate;
            _infoSpeed = info.currentSpeed;
            _nativeCadence = info.currentCadence;
        }
        if (_fitPhaseRecord != null && _state == STATE_RUNNING) {
            try {
                _fitPhaseRecord.setData(_phase);
            } catch (e) {
            }
        }
        if (_fitGlucose != null && _state == STATE_RUNNING && glucose.value != null) {
            // The glucose only changes every 1-5 minutes; setData is only
            // needed when a new reading arrived. The recording engine
            // stamps the current field value into every record message.
            var g = glucose.value.toNumber();
            if (g != _lastFitGlucose) {
                _lastFitGlucose = g;
                try {
                    _fitGlucose.setData(g);
                } catch (e) {
                }
            }
        }
        if (_fitCadence != null && _state == STATE_RUNNING) {
            // The engine does not write cadence into the records of a
            // multisport session; the app records it as a developer field
            // (0xFF = invalid, outside the bike phase / without sensor).
            try {
                _fitCadence.setData(_cadence != null ? _cadence : 0xFF);
            } catch (e) {
            }
        }
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------
    // Settings (Garmin Connect Mobile app settings)
    // ------------------------------------------------------------------

    //! Load the per-phase data field configuration from the app settings.
    function loadSettings() as Void {
        _swimFields = loadFieldConfig("swimField", [FIELD_TIME, FIELD_DISTANCE, FIELD_PACE, FIELD_HR] as Array<Number>);
        _bikeFields = loadFieldConfig("bikeField", [FIELD_TIME, FIELD_SPEED, FIELD_CADENCE, FIELD_HR] as Array<Number>);
        _runFields = loadFieldConfig("runField", [FIELD_TIME, FIELD_DISTANCE, FIELD_PACE, FIELD_HR] as Array<Number>);
    }

    //! Read one group of four field settings.
    //! @param prefix Property id prefix, e.g. "swimField"
    //! @param defaults Fallback values if the settings are missing
    //! @return Four field type ids
    function loadFieldConfig(prefix as String, defaults as Array<Number>) as Array<Number> {
        var result = new Array<Number>[4];
        for (var i = 0; i < 4; i++) {
            var value = defaults[i];
            try {
                var raw = Application.Properties.getValue(prefix + (i + 1).toString());
                if (raw != null) {
                    var candidate = raw as Number;
                    if (candidate >= FIELD_NONE && candidate <= FIELD_CGM) {
                        value = candidate;
                    }
                }
            } catch (e) {
                // Keep the default on any settings problem.
            }
            result[i] = value;
        }
        return result;
    }

    //! The configured fields for the given phase.
    //! @param phase The phase
    //! @return Four field type ids
    function getFieldsForPhase(phase as Number) as Array<Number> {
        if (phase == PHASE_BIKE && _bikeFields != null) {
            return _bikeFields;
        }
        if (phase == PHASE_RUN && _runFields != null) {
            return _runFields;
        }
        return _swimFields as Array<Number>;
    }

    // ------------------------------------------------------------------
    // Persistence
    // ------------------------------------------------------------------

    //! Persist phase and state so the exercise survives an app restart.
    function persistState() as Void {
        try {
            Application.Storage.setValue(STORAGE_PHASE, _phase);
            Application.Storage.setValue(STORAGE_PHASE_INDEX, _phaseIndex);
            Application.Storage.setValue(STORAGE_STATE, _state);
        } catch (e) {
        }
    }

    //! Restore phase and state from the application storage.
    function restoreStateFromStorage() as Void {
        _phase = restoreNumber(STORAGE_PHASE, PHASE_SWIM);
        _phaseIndex = restoreNumber(STORAGE_PHASE_INDEX, 0);
        if (_phaseIndex < 0 || _phaseIndex >= _phaseOrder.size()) {
            _phaseIndex = 0;
            _phase = PHASE_SWIM;
        }
        var storedState = restoreNumber(STORAGE_STATE, STATE_READY);
        if (storedState == STATE_SAVED) {
            // A saved activity is finalized; start fresh next time.
            storedState = STATE_READY;
        }
        _state = storedState;
    }

    //! Read a Number from the application storage.
    //! @param key Storage key
    //! @param fallback Value if nothing was stored
    //! @return The stored value or the fallback
    function restoreNumber(key as String, fallback as Number) as Number {
        try {
            var value = Application.Storage.getValue(key);
            if (value != null) {
                return value as Number;
            }
        } catch (e) {
        }
        return fallback;
    }

    // ------------------------------------------------------------------
    // Getters used by the view
    // ------------------------------------------------------------------

    //! @return Current UI state
    function getState() as Number {
        return _state;
    }

    //! @return Current phase
    function getPhase() as Number {
        return _phase;
    }

    //! @return Current timer value in milliseconds
    function getTimerTime() as Number {
        return _timerTime;
    }

    //! @return Total session distance in meters
    function getTotalDistance() as Float {
        return _elapsedDistance;
    }

    //! @return Current leg distance in meters
    function getLegDistance() as Float {
        return _legDistance;
    }

    //! @return Heart rate in bpm, or null
    function getHeartRate() as Number or Null {
        return _heartRate;
    }

    //! @return Current cadence (sensor value preferred), or null
    function getCadence() as Number or Null {
        if (_cadence != null) {
            return _cadence;
        }
        return _nativeCadence;
    }

    //! @return true if a cadence sensor is delivering data
    function getCadenceConnected() as Boolean {
        return _cadenceConnected;
    }

    //! @return Current speed in m/s, or null
    function getSpeed() as Float or Null {
        if (_infoSpeed != null) {
            return _infoSpeed;
        }
        return _gpsSpeed;
    }

    //! @return true if the GPS accuracy is usable
    function hasGpsFix() as Boolean {
        return _gpsQuality >= Position.QUALITY_USABLE;
    }
}
