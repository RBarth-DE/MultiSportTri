# MultiSportTri — Triathlon-Aufnahme mit CGM (Venu 3)

**Durchgehende Triathlon-Aufzeichnung: Schwimmen → Wechsel 1 → Radfahren → Wechsel 2 → Laufen — eine Aktivität, ein Timer, fünf Phasen.**

Der Phasenwechsel erfolgt per Rücktaste (Lap) — zuverlässig auch beim Schwimmen. Jeder Wechsel setzt einen Lap-Marker; in Garmin Connect erscheinen alle Abschnitte als eigene Runden mit Zeiten.

**Funktionen**

- **Phasen-Diagramm:** Ein FIT-Entwicklerfeld schreibt die aktuelle Phase sekündlich mit — als Kurve in Garmin Connect siehst du deinen Rennverlauf.
- **CGM (optional):** Mit dem AAPS-Garmin-Plugin zeigt ein frei platzierbares Datenfeld deinen aktuellen Zuckerwert (farbcodiert, mit Trend). Die Glukose wird zusätzlich in die FIT-Datei geschrieben — als Glukose-Kurve neben Belastung und Phasen. Ohne Plugin bleibt das Feld leer.
- **Konfigurierbare Datenfelder:** Vier Felder pro Phase (Schwimmen/Radfahren/Laufen) — direkt auf der Uhr oder über Garmin Connect Mobile: Herzfrequenz, Trittfrequenz, Distanz, Zeit, Pace, Geschwindigkeit, Zucker.
- **Robust:** Geht die App mitten im Wettkampf verloren, läuft die Aufnahme nativ weiter; beim erneuten Öffnen wird die laufende Aktivität wieder angehängt.

**Bedienung (Venu 3)**

| Taste | Zustand | Aktion |
|---|---|---|
| Start/Stop | bereit | Aufnahme starten |
| Start/Stop | Aufnahme läuft | stoppen |
| Start/Stop | gestoppt | weiter aufzeichnen |
| Rücktaste | Aufnahme läuft | nächste Phase (Lap) |
| Rücktaste | gestoppt | Menü: weiter / speichern / verwerfen |
| Menü | bereit | Datenfelder konfigurieren |

**CGM-Anbindung:** Zuckerwert vom AAPS-Garmin-Plugin auf dem Smartphone (AndroidAPS). Einheit (mg/dl oder mmol/l) wird automatisch aus der AAPS-Konfiguration übernommen.

**Hinweise:** Schwimmphase zeit- und GPS-basiert (Schwimmzug-Erkennung steht Apps nicht offen). Sub-Sportarten pro Abschnitt sind per API nicht möglich — die Abschnitte sind über Runden und Phasen-Kurve klar unterscheidbar. Nach der Installation die Uhr einmal neu starten (vermeidet den Erststart-Crash der aktuellen Beta-Firmware).

