//! On-watch UI strings, selected by the device language setting.
//!
//! Rez.Strings (resources/strings/strings.xml + strings-deu.xml) already
//! localize the Garmin Connect Mobile settings and the FIT field labels;
//! Connect IQ picks those by the phone/watch language automatically.
//! On-watch text cannot use Rez.Strings on Venu 3 firmware 17.05: the
//! runtime does not resolve ResourceIds of sideloaded apps and renders
//! the literal text "ResourceId". The strings therefore live here and
//! follow System.getDeviceSettings().language. English is the fallback.

import Toybox.Lang;
import Toybox.System;

//! True when the watch UI language is German.
//! @return true for German, false otherwise
function isGerman() as Boolean {
    return System.getDeviceSettings().systemLanguage == System.LANGUAGE_DEU;
}

//! Localized on-watch UI string.
//! @param id String id, same names as the Rez.Strings entries
//! @return German or English text (English for every other language)
function tr(id as Symbol) as String {
    var de = isGerman();

    // Phases
    if (id == :PhaseSwim) { return de ? "SCHWIMMEN" : "SWIM"; }
    if (id == :PhaseTransition1) { return de ? "WECHSEL 1" : "TRANSITION 1"; }
    if (id == :PhaseBike) { return de ? "RADFAHREN" : "BIKE"; }
    if (id == :PhaseTransition2) { return de ? "WECHSEL 2" : "TRANSITION 2"; }
    if (id == :PhaseRun) { return de ? "LAUFEN" : "RUN"; }

    // Short labels on the 2x2 data grid
    if (id == :LabelHeartRate) { return de ? "HF" : "HR"; }
    if (id == :LabelCadence) { return de ? "KADENZ" : "CADENCE"; }
    if (id == :LabelDistance) { return de ? "DISTANZ" : "DISTANCE"; }
    if (id == :LabelTime) { return de ? "ZEIT" : "TIME"; }
    if (id == :LabelPace) { return de ? "PACE" : "PACE"; }
    if (id == :LabelSpeed) { return de ? "GESCHW." : "SPEED"; }
    if (id == :LabelTotalDistance) { return de ? "DISTANZ GES." : "TOTAL DIST."; }
    if (id == :LabelCgm) { return de ? "ZUCKER" : "CGM"; }

    // Status / hints
    if (id == :StatusGpsOk) { return "GPS ✓ · START"; }
    if (id == :NoGps) { return de ? "GPS: kein Empfang" : "GPS: no fix"; }
    if (id == :HintStopped) { return de ? "START: weiter · MENÜ" : "START: resume · MENU"; }
    if (id == :HintSaved) { return de ? "Gespeichert ✓" : "Saved ✓"; }
    if (id == :CadenceNoSensor) { return de ? "Kadenz: kein Sensor" : "Cadence: no sensor"; }
    if (id == :HintLap) { return de ? "LAP: nächste Phase" : "LAP: next phase"; }

    // Context menu
    if (id == :MenuSave) { return de ? "Speichern & beenden" : "Save & End"; }
    if (id == :MenuDiscard) { return de ? "Aufnahme verwerfen" : "Discard Recording"; }
    if (id == :MenuResume) { return de ? "Weiter aufzeichnen" : "Resume"; }
    if (id == :MenuCancel) { return de ? "Abbrechen" : "Cancel"; }
    if (id == :MenuNew) { return de ? "Neue Aktivität" : "New Activity"; }

    // On-watch data field configuration
    if (id == :ConfigTitle) { return de ? "Datenfelder" : "Data Fields"; }
    if (id == :SettingsSwimTitle) { return de ? "Schwimmen" : "Swim"; }
    if (id == :SettingsBikeTitle) { return de ? "Radfahren" : "Bike"; }
    if (id == :SettingsRunTitle) { return de ? "Laufen" : "Run"; }
    if (id == :SlotTitle) { return de ? "Feld wählen" : "Select Field"; }
    if (id == :SettingsSlot1) { return de ? "Feld 1" : "Field 1"; }
    if (id == :SettingsSlot2) { return de ? "Feld 2" : "Field 2"; }
    if (id == :SettingsSlot3) { return de ? "Feld 3" : "Field 3"; }
    if (id == :SettingsSlot4) { return de ? "Feld 4" : "Field 4"; }
    if (id == :ValueTitle) { return de ? "Wert wählen" : "Select Value"; }
    if (id == :FieldHeartRate) { return de ? "Herzfrequenz" : "Heart Rate"; }
    if (id == :FieldCadence) { return de ? "Trittfrequenz" : "Cadence"; }
    if (id == :FieldDistance) { return de ? "Distanz" : "Distance"; }
    if (id == :FieldTime) { return de ? "Zeit" : "Time"; }
    if (id == :FieldPace) { return de ? "Pace" : "Pace"; }
    if (id == :FieldSpeed) { return de ? "Geschwindigkeit" : "Speed"; }
    if (id == :FieldCgm) { return de ? "Zucker (CGM)" : "CGM Glucose"; }
    if (id == :FieldNone) { return de ? "- Aus -" : "- Off -"; }

    return "";
}
