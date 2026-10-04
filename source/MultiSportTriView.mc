//! Main view of MultiSportTri: large colored phase band, big timer and
//! a 2x2 grid of configurable data fields, plus a status line.
//!
//! Layout (Venu 3, 454 x 454 round AMOLED):
//!   * 0..64       phase band (colored, large phase name)
//!   * 64..190     timer (huge number font)
//!   * 194..414    2x2 data field grid
//!   * 414..454    status / hint line

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! All vertical positions are anchored to the screen center (like the
//! known-good AAPS widget): on a round display the circle is widest in
//! the middle, so center-anchored content always fits, whatever the real
//! canvas size is.
const PHASE_OFF = -170;    // phase name (colored)
const TIMER_OFF = -128;    // big running timer
const ROW1_OFF = -30;      // 2x2 grid, first row
const ROW2_OFF = 64;       // 2x2 grid, second row
const STATUS_OFF = 150;    // status / hint line
//! Outer margin of the data field cells (inscribed square of the
//! visible circle).
const SCREEN_MARGIN = 52;
//! Horizontal gap between the left and right column.
const CENTER_GAP = 14;

class MultiSportTriView extends WatchUi.View {

    private var _app as MultiSportTriApp;

    //! Constructor
    //! @param app The application instance
    function initialize(app as MultiSportTriApp) {
        View.initialize();
        _app = app;
    }

    //! Update the view
    //! @param dc Device context
    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var phase = _app.getPhase();
        var state = _app.getState();

        drawPhaseLabel(dc, cx, cy, phase);
        drawTimer(dc, cx, cy);
        drawFieldGrid(dc, dc.getWidth(), cy, phase);
        drawStatusLine(dc, cx, cy, state, phase);
    }

    //! Colored phase name above the timer (text only: a filled band
    //! rectangle always has clipped corners on a round display).
    //! @param dc Device context
    //! @param cx Screen center x
    //! @param cy Screen center y
    //! @param phase Current phase
    function drawPhaseLabel(dc as Dc, cx as Number, cy as Number, phase as Number) as Void {
        dc.setColor(phaseColor(phase), Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            cy + PHASE_OFF,
            Graphics.FONT_MEDIUM,
            phaseName(phase),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! The big running timer.
    //! @param dc Device context
    //! @param cx Screen center x
    //! @param cy Screen center y
    function drawTimer(dc as Dc, cx as Number, cy as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx,
            cy + TIMER_OFF,
            Graphics.FONT_NUMBER_MEDIUM,
            formatClock(_app.getTimerTime()),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! The 2x2 data field grid. During the transitions the fields are
    //! fixed (time, total distance, heart rate), during the sport phases
    //! they come from the app settings (configurable in Garmin Connect
    //! Mobile, four fields per phase).
    //! @param dc Device context
    //! @param width Screen width
    //! @param cy Screen center y
    //! @param phase Current phase
    function drawFieldGrid(dc as Dc, width as Number, cy as Number, phase as Number) as Void {
        var fields = null;
        if (phase == PHASE_T1 || phase == PHASE_T2) {
            fields = [FIELD_TIME, FIELD_TOTAL_DISTANCE, FIELD_HR, FIELD_NONE] as Array<Number>;
        } else {
            fields = _app.getFieldsForPhase(phase);
        }
        var cellWidth = (width - 2 * SCREEN_MARGIN - CENTER_GAP) / 2;
        for (var i = 0; i < fields.size(); i++) {
            var col = i % 2;
            var row = i / 2;
            drawFieldCell(
                dc,
                SCREEN_MARGIN + col * (cellWidth + CENTER_GAP),
                cy + (row == 0 ? ROW1_OFF : ROW2_OFF),
                cellWidth,
                fields[i],
                phase
            );
        }
    }

    //! Draw one data field cell (small label above a large value).
    //! @param dc Device context
    //! @param x Cell left
    //! @param y Cell top
    //! @param width Cell width
    //! @param fieldType Field type id
    //! @param phase Current phase (for unit selection)
    function drawFieldCell(dc as Dc, x as Number, y as Number, width as Number, fieldType as Number, phase as Number) as Void {
        if (fieldType == FIELD_NONE) {
            return;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x + width / 2, y + 2,
            Graphics.FONT_XTINY,
            labelForField(fieldType),
            Graphics.TEXT_JUSTIFY_CENTER
        );
        // The CGM value is colored by range/staleness, all others white.
        var valueColor = fieldType == FIELD_CGM ? glucose.color() : Graphics.COLOR_WHITE;
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            x + width / 2, y + 30,
            Graphics.FONT_LARGE,
            valueForField(fieldType, phase),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! Status / hint line.
    //! @param dc Device context
    //! @param cx Screen center x
    //! @param cy Screen center y
    //! @param state Current state
    //! @param phase Current phase
    function drawStatusLine(dc as Dc, cx as Number, cy as Number, state as Number, phase as Number) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(
            cx, cy + STATUS_OFF,
            Graphics.FONT_XTINY,
            statusLine(state, phase),
            Graphics.TEXT_JUSTIFY_CENTER
        );
    }

    //! The status text for the current state.
    //! @param state Current state
    //! @param phase Current phase
    //! @return Status text
    function statusLine(state as Number, phase as Number) as String {
        if (state == STATE_READY) {
            return _app.hasGpsFix() ? tr(:StatusGpsOk) : tr(:NoGps);
        }
        if (state == STATE_STOPPED) {
            return tr(:HintStopped);
        }
        if (state == STATE_SAVED) {
            return tr(:HintSaved);
        }
        if (phase == PHASE_BIKE && !_app.getCadenceConnected()) {
            return tr(:CadenceNoSensor);
        }
        if (phase == PHASE_SWIM && !_app.hasGpsFix()) {
            return tr(:NoGps);
        }
        return tr(:HintLap);
    }

    // ------------------------------------------------------------------
    // Formatting helpers
    // ------------------------------------------------------------------

    //! Format milliseconds as a clock ("1:23:45" or "23:45").
    //! @param ms Timer value in milliseconds
    //! @return Formatted time
    function formatClock(ms as Number) as String {
        // Integer division/modulo only: Math.floor() returns a Float and
        // the % operator throws on Float operands (crashed on first draw).
        var totalSeconds = (ms / 1000.0).toNumber();
        var hours = totalSeconds / 3600;
        var minutes = (totalSeconds / 60) % 60;
        var seconds = totalSeconds % 60;
        if (hours > 0) {
            return hours.format("%d") + ":" + twoDigits(minutes) + ":" + twoDigits(seconds);
        }
        return minutes.format("%d") + ":" + twoDigits(seconds);
    }

    //! Zero-padded two-digit number.
    //! @param value Number to format
    //! @return Two-digit string
    function twoDigits(value as Number) as String {
        return value < 10 ? "0" + value.format("%d") : value.format("%d");
    }

    //! Format a distance according to the device units. The swim leg is
    //! shown in meters (yards), the other legs in kilometers (miles).
    //! @param meters Distance in meters
    //! @param phase Current phase
    //! @return Formatted distance
    function formatDistance(meters as Float, phase as Number) as String {
        var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        if (phase == PHASE_SWIM) {
            if (isMetric) {
                return meters.toNumber().format("%d") + " m";
            }
            return (meters * 1.09361).toNumber().format("%d") + " yd";
        }
        if (isMetric) {
            if (meters >= 10000.0) {
                return (meters / 1000.0).format("%.1f") + " km";
            }
            return (meters / 1000.0).format("%.2f") + " km";
        }
        if (meters >= 16093.4) {
            return (meters / 1609.34).format("%.1f") + " mi";
        }
        return (meters / 1609.34).format("%.2f") + " mi";
    }

    //! Format a speed as pace (min/km or min/mi).
    //! @param speed Speed in m/s
    //! @return Pace string like "5:42", or "--" without speed
    function formatPace(speed as Float) as String {
        if (speed < 0.3) {
            return "--";
        }
        var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        var metersPerUnit = isMetric ? 1000.0 : 1609.34;
        var secondsPerUnit = metersPerUnit / speed;
        var totalSeconds = Math.floor(secondsPerUnit + 0.5).toNumber();
        var minutes = totalSeconds / 60;
        var seconds = totalSeconds % 60;
        return minutes.format("%d") + ":" + twoDigits(seconds);
    }

    //! Format a speed as km/h or mph.
    //! @param speed Speed in m/s
    //! @return Speed string, or "--" without speed
    function formatSpeed(speed as Float) as String {
        if (speed < 0.0) {
            return "--";
        }
        var isMetric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        if (isMetric) {
            return (speed * 3.6).format("%.1f");
        }
        return (speed * 2.23694).format("%.1f");
    }

    // ------------------------------------------------------------------
    // Data field values
    // ------------------------------------------------------------------

    //! The display label for a field type.
    //! @param fieldType Field type id
    //! @return Short label
    function labelForField(fieldType as Number) as String {
        if (fieldType == FIELD_HR) {
            return tr(:LabelHeartRate);
        }
        if (fieldType == FIELD_CADENCE) {
            return tr(:LabelCadence);
        }
        if (fieldType == FIELD_DISTANCE) {
            return tr(:LabelDistance);
        }
        if (fieldType == FIELD_TIME) {
            return tr(:LabelTime);
        }
        if (fieldType == FIELD_PACE) {
            return tr(:LabelPace);
        }
        if (fieldType == FIELD_SPEED) {
            return tr(:LabelSpeed);
        }
        if (fieldType == FIELD_TOTAL_DISTANCE) {
            return tr(:LabelTotalDistance);
        }
        if (fieldType == FIELD_CGM) {
            return tr(:LabelCgm);
        }
        return "";
    }

    //! The display value for a field type.
    //! @param fieldType Field type id
    //! @param phase Current phase
    //! @return Formatted value
    function valueForField(fieldType as Number, phase as Number) as String {
        if (fieldType == FIELD_HR) {
            var heartRate = _app.getHeartRate();
            return heartRate != null ? heartRate.format("%d") : "--";
        }
        if (fieldType == FIELD_CADENCE) {
            var cadence = _app.getCadence();
            return cadence != null ? cadence.format("%d") : "--";
        }
        if (fieldType == FIELD_DISTANCE) {
            return formatDistance(_app.getLegDistance(), phase);
        }
        if (fieldType == FIELD_TOTAL_DISTANCE) {
            return formatDistance(_app.getTotalDistance(), phase);
        }
        if (fieldType == FIELD_TIME) {
            return formatClock(_app.getTimerTime());
        }
        if (fieldType == FIELD_PACE) {
            var speed = _app.getSpeed();
            return speed != null ? formatPace(speed) : "--";
        }
        if (fieldType == FIELD_SPEED) {
            var speed = _app.getSpeed();
            return speed != null ? formatSpeed(speed) : "--";
        }
        if (fieldType == FIELD_CGM) {
            return glucose.valueText();
        }
        return "";
    }

    // ------------------------------------------------------------------
    // Phase presentation
    // ------------------------------------------------------------------

    //! The localized name for a phase (see L10n.mc — Rez.Strings cannot
    //! be used on-watch with firmware 17.05 sideloaded apps).
    //! @param phase The phase
    //! @return Phase name
    function phaseName(phase as Number) as String {
        if (phase == PHASE_SWIM) {
            return tr(:PhaseSwim);
        }
        if (phase == PHASE_T1) {
            return tr(:PhaseTransition1);
        }
        if (phase == PHASE_BIKE) {
            return tr(:PhaseBike);
        }
        if (phase == PHASE_T2) {
            return tr(:PhaseTransition2);
        }
        return tr(:PhaseRun);
    }

    //! The band color for a phase.
    //! @param phase The phase
    //! @return Color value
    function phaseColor(phase as Number) as Number {
        if (phase == PHASE_SWIM) {
            return 0x2F7CF6; // blue
        }
        if (phase == PHASE_T1 || phase == PHASE_T2) {
            return 0xFFB300; // amber
        }
        if (phase == PHASE_BIKE) {
            return 0x00C853; // green
        }
        return 0xFF5252;     // red (run)
    }
}
