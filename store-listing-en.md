# MultiSportTri — Triathlon recording with CGM (Venu 3)

**One continuous triathlon recording: Swim → Transition 1 → Bike → Transition 2 → Run — a single activity, one timer, five phases.**

Phase changes happen with the Back/Lap button — reliable even while swimming. Every change writes a lap marker; Garmin Connect shows all sections as separate laps with individual times.

**Features**

- **Phase chart:** A FIT developer field records the current phase every second — the curve in Garmin Connect shows your race flow at a glance.
- **CGM (optional):** With the AAPS Garmin plugin, a freely placeable data field shows your current glucose (color-coded, with trend). Glucose is also written into the FIT file — a glucose curve next to effort and phases. Without the plugin the field stays empty.
- **Configurable data fields:** Four fields per phase (swim/bike/run) — directly on the watch or via Garmin Connect Mobile: heart rate, cadence, distance, time, pace, speed, glucose.
- **Robust:** Lost the app mid-race? The recording continues natively; reopening the app re-attaches to the running activity.

**Buttons (Venu 3)**

| Button | State | Action |
|---|---|---|
| Start/Stop | ready | start recording |
| Start/Stop | recording | stop |
| Start/Stop | stopped | resume |
| Back | recording | next phase (lap) |
| Back | stopped | menu: resume / save / discard |
| Menu | ready | configure data fields |

**CGM connection:** Glucose comes from the AAPS Garmin plugin on your phone (AndroidAPS). The unit (mg/dl or mmol/l) is taken from your AAPS configuration automatically.

**Notes:** The swim leg is time- and GPS-based (stroke detection is not available to apps). Per-leg sub-sports are not possible via the API — legs are clearly distinguishable via laps and the phase chart. Restart the watch once after installation (avoids a first-launch crash of the current beta firmware).
