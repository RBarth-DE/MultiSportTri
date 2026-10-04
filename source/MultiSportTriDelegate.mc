//! Input handling for MultiSportTri.
//!
//! Buttons on the Venu 3 (enter / menu / esc):
//!   * enter  = Start/Stop: starts, resumes and saves the recording
//!   * esc    = Back/Lap:   phase change while recording; otherwise back
//!   * menu   = context menu (save / discard / resume)
//!
//! While the recording is running the Venu 3 delivers LAP/Back as a
//! stream of onBack() behaviors (never raw key 5, never TIMER_EVENT_LAP).
//! Short press = one or two onBack events then quiet → one phase change.
//! Long press = slow onBack repeat stream + key 7 → native stop menu.

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MultiSportTriDelegate extends WatchUi.BehaviorDelegate {

    private var _app as MultiSportTriApp;
    //! Extra LAP key events (key 5) seen outside onBack; the Venu 3
    //! normally uses onBack only. Used only to classify key 7.
    private var _lapKeyCount as Number = 0;

    //! Constructor
    //! @param app The application instance
    function initialize(app as MultiSportTriApp) {
        BehaviorDelegate.initialize();
        _app = app;
    }

    //! Handle a key press.
    //! @param keyEvent The key event
    //! @return true if the event was handled
    function onKey(keyEvent as KeyEvent) as Boolean {
        var key = keyEvent.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START || key == 4) {
            _lapKeyCount = 0;
            return onStartKey();
        }
        // Venu 3 reports the LAP/Back button as key 5 (KEY_ESC/KEY_LAP
        // when those constants match). Accept all of them.
        if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP || key == 5) {
            return onBackKey();
        }
        if (key == WatchUi.KEY_MENU) {
            return onMenuKey();
        }
        if (key == 7) {
            // Long-press marker of the Lap/Back button. It often arrives
            // AFTER the quiet-gap timer has already ended the gesture
            // (count already cleared), so ask the app whether that
            // gesture was a long press. Long press → false (native stop
            // menu). Short press → true (consume; no menu).
            var wasLong = _app.isLongPressGesture()
                || _app.wasLastGestureLong()
                || _lapKeyCount >= 3;
            _app.finishLapGesture(true);
            _lapKeyCount = 0;
            return wasLong ? false : true;
        }
        // Some devices report the menu button with a device-specific key
        // code that does not match WatchUi.KEY_MENU. In the READY state
        // every unhandled key opens the field configuration (the watch
        // has no other buttons to press there).
        if (_app.getState() == STATE_READY) {
            return onMenuKey();
        }
        return false;
    }

    //! Back behavior — the path the Venu 3 actually uses for the
    //! LAP/Back button (onKey is never called with key 5). Counts as one
    //! event in the current LAP gesture; the phase advances when the
    //! gesture ends (see MultiSportTriApp.finishLapGesture).
    //! @return true if handled
    function onBack() as Boolean {
        return onBackKey();
    }

    //! enter / Start-Stop button.
    //! @return true if handled
    function onStartKey() as Boolean {
        var state = _app.getState();
        if (state == STATE_READY) {
            return _app.startRecording();
        }
        if (state == STATE_STOPPED || state == STATE_PAUSED) {
            return _app.resumeRecording();
        }
        if (state == STATE_SAVED) {
            _app.resetToReady();
            return true;
        }
        // While recording: stop explicitly. On devices where the native
        // recording engine consumes this button it never reaches us and
        // the TIMER_EVENT_STOP handler runs instead.
        return _app.stopRecording();
    }

    //! esc / Back-Lap button.
    //! @return true if handled
    function onBackKey() as Boolean {
        var state = _app.getState();
        if (_app.isRecording()) {
            // The Venu 3 delivers this as onBack() only (no KEY_LAP and
            // no TIMER_EVENT_LAP). Count it into the current gesture; the
            // phase advances once when the gesture ends, never during a
            // long-press repeat stream (that must only open the stop menu).
            _app.requestPhaseAdvance();
            return true;
        }
        if (state == STATE_STOPPED || state == STATE_SAVED) {
            showMenu();
            return true;
        }
        // Ready state: leave the app.
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        return true;
    }

    //! menu button: context menu depending on the state.
    //! @return true if handled
    function onMenuKey() as Boolean {
        var state = _app.getState();
        if (state == STATE_READY) {
            showConfigMenu();
            return true;
        }
        showMenu();
        return true;
    }

    //! On-watch data field configuration (READY state), analogous to the
    //! editable data screens of native activities. The selection is stored
    //! in the app properties under the same keys Garmin Connect Mobile
    //! uses for its app settings.
    function showConfigMenu() as Void {
        var menu = new WatchUi.Menu2({:title => tr(:ConfigTitle)});
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsSwimTitle), null, :phaseSwim, null));
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsBikeTitle), null, :phaseBike, null));
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsRunTitle), null, :phaseRun, null));
        WatchUi.pushView(menu, new FieldConfigDelegate(_app), WatchUi.SLIDE_UP);
    }

    //! Build and show the context menu for the current state.
    //! Localized via L10n.mc (see the note there about Rez.Strings).
    function showMenu() as Void {
        var menu = new WatchUi.Menu2({
            :title => "MultiSportTri"
        });
        var state = _app.getState();
        if (state == STATE_RUNNING || state == STATE_PAUSED) {
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuSave), null, :save, null));
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuDiscard), null, :discard, null));
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuCancel), null, :cancel, null));
        } else if (state == STATE_STOPPED) {
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuResume), null, :resume, null));
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuSave), null, :save, null));
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuDiscard), null, :discard, null));
        } else if (state == STATE_SAVED) {
            menu.addItem(new WatchUi.MenuItem(
                tr(:MenuNew), null, :new, null));
        }
        WatchUi.pushView(menu, new MultiSportTriMenuDelegate(_app), WatchUi.SLIDE_UP);
    }
}

//! Delegate for the on-watch data field configuration: phase -> slot ->
//! field type. The values are written to the same properties the Garmin
//! Connect Mobile app settings use (swimField1..4, bikeField1..4,
//! runField1..4).
class FieldConfigDelegate extends WatchUi.Menu2InputDelegate {

    private var _app as MultiSportTriApp;
    //! Property prefix of the chosen phase ("" until chosen).
    private var _prefix as String = "";
    //! Slot being configured (1..4, 0 until chosen).
    private var _slot as Number = 0;

    //! Constructor
    //! @param app The application instance
    function initialize(app as MultiSportTriApp) {
        Menu2InputDelegate.initialize();
        _app = app;
    }

    //! Handle a selected menu item.
    //! @param item The selected item
    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);

        if (id == :phaseSwim || id == :phaseBike || id == :phaseRun) {
            _prefix = id == :phaseSwim ? "swimField"
                : id == :phaseBike ? "bikeField" : "runField";
            showSlotMenu();
        } else if (id == :slot1 || id == :slot2 || id == :slot3 || id == :slot4) {
            _slot = id == :slot1 ? 1 : id == :slot2 ? 2 : id == :slot3 ? 3 : 4;
            showFieldMenu();
        } else {
            var value = FIELD_NONE;
            if (id == :fhr) {
                value = FIELD_HR;
            } else if (id == :fcad) {
                value = FIELD_CADENCE;
            } else if (id == :fdist) {
                value = FIELD_DISTANCE;
            } else if (id == :ftime) {
                value = FIELD_TIME;
            } else if (id == :fpace) {
                value = FIELD_PACE;
            } else if (id == :fspeed) {
                value = FIELD_SPEED;
            } else if (id == :fcgm) {
                value = FIELD_CGM;
            }
            Application.Properties.setValue(_prefix + _slot.toString(), value);
            _app.loadSettings();
            WatchUi.requestUpdate();
            // Back to the slot menu of the same phase, so several fields
            // can be configured in one pass (like native data screens).
            showSlotMenu();
        }
    }

    //! Show the slot menu (field 1..4) of the chosen phase.
    function showSlotMenu() as Void {
        var menu = new WatchUi.Menu2({:title => tr(:SlotTitle)});
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsSlot1), null, :slot1, null));
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsSlot2), null, :slot2, null));
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsSlot3), null, :slot3, null));
        menu.addItem(new WatchUi.MenuItem(tr(:SettingsSlot4), null, :slot4, null));
        WatchUi.pushView(menu, self, WatchUi.SLIDE_UP);
    }

    //! Show the field type menu for the chosen slot.
    function showFieldMenu() as Void {
        var menu = new WatchUi.Menu2({:title => tr(:ValueTitle)});
        menu.addItem(new WatchUi.MenuItem(tr(:FieldHeartRate), null, :fhr, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldCadence), null, :fcad, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldDistance), null, :fdist, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldTime), null, :ftime, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldPace), null, :fpace, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldSpeed), null, :fspeed, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldCgm), null, :fcgm, null));
        menu.addItem(new WatchUi.MenuItem(tr(:FieldNone), null, :fnone, null));
        WatchUi.pushView(menu, self, WatchUi.SLIDE_UP);
    }
}

//! Delegate for the context menu.
class MultiSportTriMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _app as MultiSportTriApp;

    //! Constructor
    //! @param app The application instance
    function initialize(app as MultiSportTriApp) {
        Menu2InputDelegate.initialize();
        _app = app;
    }

    //! Handle a selected menu item.
    //! @param item The selected item
    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        if (id == :save) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _app.saveSession();
        } else if (id == :discard) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _app.discardSession();
        } else if (id == :resume) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _app.resumeRecording();
        } else if (id == :new) {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            _app.resetToReady();
        } else {
            // :cancel - close the menu and continue.
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    //! Back key closes the menu without action.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
