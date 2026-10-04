//! Watch-app entry point using the getInitialView pattern (no onStart UI
//! push). Diagnostic variant: some device firmwares crash watch-apps that
//! push their view from onStart, while the getInitialView entry works.

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MultiSportTriGetInitApp extends MultiSportTriApp {

    function initialize() {
        MultiSportTriApp.initialize();
    }

    //! Called when the app is launched: initialization only, the UI is
    //! provided by getInitialView().
    //! @param state Startup state
    function onStart(state as Dictionary or Null) as Void {
        initCore();
    }

    //! Return the initial view of the app.
    function getInitialView() {
        return [new MultiSportTriView(self), new MultiSportTriDelegate(self)];
    }
}
