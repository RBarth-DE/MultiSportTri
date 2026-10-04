Aufgabe: 
Entwickle eine Garmin Connect I.Q. Watch App namens MultiSportTri für die Venu 3, geschrieben in Monkey C, die eine durchgehende Triathlon-Aufnahme mit manuellem Wechsel zwischen drei internen Sportarten ermöglicht, Schwimmen, Radfahren und Laufen, ohne die Aktivitätsaufzeichnung zu unterbrechen.

Funktionale Anforderungen: 
Erstens, beim App-Start wird über Toybox Punkt Activity Recording eine einzige Session erzeugt mit Sportart Multisport oder Triathlon, die während der gesamten Übung offen bleibt. 

Zweitens, die App verwaltet einen internen Zustand mit den drei Phasen Schwimmen, Radfahren, Laufen, sowie einer Übergangsphase dazwischen. 

Drittens, der Nutzer wechselt die Phase über einen expliziten Knopfdruck, zum Beispiel die Start-Stopp-Taste lang drücken oder eine Menütaste, nicht über Touch, da Touch beim Schwimmen unzuverlässig ist. 

Viertens, bei jedem Phasenwechsel wird ein Lap Marker gesetzt und die Sub-Sportart der Session aktualisiert, die Aufnahme läuft aber durchgehend weiter. 

Fünftens, während der Radfahren-Phase soll die App über die Sensor-Pairing-A.P.I. einen Trittfrequenz-Sensor per Bluetooth oder ant plus einbinden und dessen Werte im Datenfeld anzeigen und aufzeichnen. 

Sechstens, während der Schwimmen-Phase soll möglichst die interne GPS- oder Beschleunigungssensor-basierte Schwimmerkennung der Venu 3 genutzt werden, sofern die A.P.I. das zulässt, ansonsten rein zeit- und distanzbasierte Aufzeichnung. 

Siebtens, am Ende wird die Session gespeichert mit allen dreien Phasen als klar unterscheidbare Abschnitte in der f.i.t.-Datei, sodass Garmin Connect sie separat auswerten kann, ähnlich wie bei einem nativen Multisport-Profil.

Achtens, die App sollte über das Menu-Punkt Properties und Settings System konfigurierbare Datenfelder bieten, pro Phase Schwimmen, Radfahren, Laufen bis zu vier frei wählbare Datenfelder aus den Standard-Feldern wie Herzfrequenz, Trittfrequenz, Distanz, Zeit, Pace, Geschwindigkeit, und dass diese Auswahl über die Garmin Connect Mobile App als App-Einstellungen einstellbar ist, analog zu den editierbaren Datenseiten bei nativen Profilen.

Nicht-funktionale Anforderungen: robuste Fehlerbehandlung, falls der Trittfrequenz-Sensor sich nicht verbindet, klare, einfache Benutzeroberfläche mit großer Anzeige der aktuellen Phase, und Kompatibilität mit dem Connect I.Q. S.D.K. in einer aktuellen Version, geprüft im Simulator für die Venu 3.
