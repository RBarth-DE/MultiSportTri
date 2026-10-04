# MultiSportTri

Connect-IQ-Watch-App für die **Garmin Venu 3** (Monkey C, SDK 8.4.0): eine
**durchgehende Triathlon-Aufnahme** (Schwimmen → Radfahren → Laufen) mit
manuellen Phasenwechseln per Knopfdruck — ohne Unterbrechung der
Aktivitätsaufzeichnung.

## Funktionsumfang

* **Eine einzige Aufnahmesession** (`SPORT_MULTISPORT` /
  `SUB_SPORT_TRIATHLON`) bleibt vom Start bis zum Speichern offen.
* **Phasenfolge:** Schwimmen → Wechsel 1 → Radfahren → Wechsel 2 → Laufen.
  Jeder Phasenwechsel erzeugt einen neuen Lap in der FIT-Datei, der Timer
  läuft durchgehend weiter.
* **Phasenwechsel nur per Taste** (nie über Touch): Während der Aufnahme
  schluckt die native Aufnahme-Engine die Tasten; die Rücktaste (Back/Lap)
  löst den Wechsel aus — zuverlässig auch beim Schwimmen. Ein versehentlicher
  zusätzlicher Druck in der letzten Phase (Laufen) erzeugt nur einen
  weiteren Lap, setzt aber keine Messwerte zurück.
* **Trittfrequenzsensor** (ANT+ oder BLE) wird nur während der Radphase
  aktiviert und in den Datenfeldern angezeigt; die Werte fließen in die
  Aufnahme ein. Ohne Sensor bleiben die übrigen Felder voll nutzbar.
* **Schwimmen:** Die öffentliche Connect-IQ-API bietet keine
  Schwimmzüge-Erkennung für Apps, daher wird die Schwimmphase zeit- und
  GPS-distanzbasiert aufgezeichnet (Freiwasser).
* **Konfigurierbare Datenfelder:** Pro Phase (Schwimmen/Radfahren/Laufen)
  vier frei wählbare Felder aus Herzfrequenz, Trittfrequenz, Distanz, Zeit,
  Pace und Geschwindigkeit — einstellbar über die Garmin-Connect-Mobile-App
  (App-Einstellungen), analog zu den editierbaren Datenseiten nativer
  Profile.
* **Robuste Fehlerbehandlung:** fehlender Trittfrequenzsensor, fehlendes
  GPS, abgebrochene Sensoren und App-Neustart mitten im Wettkampf werden
  abgefangen. Die Aufnahme läuft auch nach einem versehentlichen
  App-Exit nativ weiter; beim erneuten Öffnen wird die Session
  wieder angehängt.

## Bedienung (Venu 3)

| Taste | Zustand | Aktion |
|---|---|---|
| Start/Stop (oben rechts) | bereit | Aufnahme starten |
| Start/Stop | Aufnahme läuft | Aufnahme stoppen (pausiert; Daten bleiben erhalten) |
| Start/Stop | gestoppt | weiter aufzeichnen |
| **Rücktaste** (unten rechts) | Aufnahme läuft | **nächste Phase** (Lap + Vibration) |
| Menü (oben links) | Aufnahme läuft | Menü: Speichern & beenden / Verwerfen |
| Menü | gestoppt | Menü: Weiter / Speichern / Verwerfen |
| Rücktaste | bereit | App beenden |

Das Display zeigt oben ein großes farbiges Phasenband, darunter den
großen Timer, ein 2×2-Datenfeldraster und eine Statuszeile
(z. B. Kadenzsensor-Status oder GPS-Empfang).

## Datenfelder konfigurieren

In **Garmin Connect Mobile** → Gerät → Apps/Aktivitäten → MultiSportTri →
Einstellungen: drei Gruppen (Schwimmen, Radfahren, Laufen) mit je vier
Feldern. Verfügbar: Herzfrequenz, Trittfrequenz, Distanz, Zeit, Pace,
Geschwindigkeit, „- Aus -".

## Trittfrequenzsensor verbinden

Der Sensor wird wie üblich in den **Uhreneinstellungen** (Sensoren &
Zubehör) oder über Garmin Connect gekoppelt. Die App aktiviert den Sensor
automatisch bei Eintritt in die Radphase und zeigt den Status in der
Statuszeile („Kadenz: kein Sensor", falls nichts verbunden ist).

## FIT-Struktur / Auswertung in Garmin Connect

* Die Aktivität wird als **Multisport (Triathlon)** aufgezeichnet; jeder
  Phasenwechsel ist ein **Lap**.
* Zusätzlich schreibt die App zwei **FIT-Entwicklerfelder**:
  * `Phase` (Record-Ebene, 1 Hz) → Diagramm „Phase" in Garmin Connect,
  * `Phase (Runde)` (Lap-Ebene) → Phasenspalte in der Rundentabelle.
  * Kodierung: 1 = Schwimmen, 2 = Wechsel 1, 3 = Radfahren,
    4 = Wechsel 2, 5 = Laufen.
* Damit sind die drei Disziplinen in Garmin Connect klar unterscheidbar
  und separat auswertbar.

### API-Einschränkungen (wichtig)

* Die öffentliche Connect-IQ-API hat **kein `setSubSport`**: die
  Sub-Sportart pro Leg kann von einer App nicht direkt in die FIT-Datei
  geschrieben werden (das kann nur das native Multisport-Profil der Uhr).
  Die Unterscheidbarkeit der Abschnitte wird stattdessen über die Laps
  plus die beiden Entwicklerfelder hergestellt.
* Die Venu-3-API exportiert `SPORT_TRIATHLON` nicht; verwendet wird
  `SPORT_MULTISPORT` + `SUB_SPORT_TRIATHLON`.
* **Schwimmzüge-/Bahnenerkennung** ist für Apps nicht zugänglich —
  Schwimmen wird als Freiwasser (GPS + Zeit) aufgezeichnet.

## Projektstruktur & Build

```
manifest.xml                 App-Definition (watch-app, venu3, Rechte)
monkey.jungle                Build-Konfiguration
resources/strings/*.xml      Texte (Englisch + Deutsch)
resources/settings/properties.xml   12 Einstellungen (3 x 4 Datenfelder)
resources/resources.xml      FIT-Entwicklerfelder (fitContributions)
resources/drawables/         70x70-Launcher-Icon
source/MultiSportTriApp.mc   Session, Phasen-Zustandsmaschine, Sensoren,
                             GPS, FIT-Felder, Einstellungen
source/MultiSportTriView.mc  UI (Phasenband, Timer, 2x2-Raster)
source/MultiSportTriDelegate.mc  Tasten & Menüs
```

Bauen (SDK 8.4.0, Entwicklerschlüssel aus dem GarminWidget-Projekt):

```bash
monkeyc -f monkey.jungle -d venu3 -y <pfad>/private_key.der \
        -o bin/MultiSportTri.prg          # Debug-Build (Simulator)
monkeyc -f monkey.jungle -d venu3 -y <pfad>/private_key.der \
        -o bin/MultiSportTri.iq -r -e     # Release-Build (Uhr)
```

Simulator: `connectiq` starten, dann `monkeydo bin/MultiSportTri.prg venu3`.
(Hinweis Arch Linux: der Simulator benötigt `webkit2gtk` **4.0** sowie
`libsoup-2.4` — beides nicht in den offiziellen Repos, siehe AUR.)

## Berechtigungen

`Fit` (Aktivitätsaufzeichnung), `FitContributor` (Entwicklerfelder),
`Sensor` (Trittfrequenz), `Positioning` (GPS).
