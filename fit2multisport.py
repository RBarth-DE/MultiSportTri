#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""fit2multisport.py — MultiSportTri-FIT in ein echtes Multisport-FIT konvertieren.

Liest die von MultiSportTri aufgezeichnete FIT-Datei (eine Session, 5 Runden
mit den Phasen Schwimmen / Wechsel 1 / Radfahren / Wechsel 2 / Laufen) und
erzeugt daraus eine Multisport-FIT-Datei mit fünf Session-Abschnitten und den
korrekten Sportarten. Garmin Connect zeigt die importierte Datei dann wie ein
natives Triathlon-Event (Sportarten pro Abschnitt, Wechsel, Gesamtauswertung).

Benutzung:
    python3 fit2multisport.py aktivitaet.fit
    python3 fit2multisport.py aktivitaet.fit triathlon_multisport.fit

Abhängigkeiten: keine (reines Python 3, nur Standardbibliothek).
Hinweis: Die CGM-Glukosekurve bleibt in der Originaldatei erhalten; die
Multisport-Datei enthält die Sport-Struktur (Positionen, HF, Kadenz, Distanz).
"""

import struct
import sys

# ---------------------------------------------------------------------------
# FIT-Grundlagen
# ---------------------------------------------------------------------------

# Globale Message-Nummern
MSG_FILE_ID = 0
MSG_SESSION = 18
MSG_LAP = 19
MSG_RECORD = 20
MSG_EVENT = 21
MSG_ACTIVITY = 34

# Sportarten (FIT-Profile)
SPORT_SWIM = 5
SPORT_TRANSITION = 3
SPORT_CYCLING = 2
SPORT_RUNNING = 1

# (sport, sub_sport) pro Phase: Schwimmen (Freiwasser), Wechsel 1, Rad, Wechsel 2, Laufen
LEG_PROFILES = [
    (SPORT_SWIM, 18),
    (SPORT_TRANSITION, 0),
    (SPORT_CYCLING, 0),
    (SPORT_TRANSITION, 0),
    (SPORT_RUNNING, 0),
]
LEG_NAMES = ["Schwimmen", "Wechsel 1", "Radfahren", "Wechsel 2", "Laufen"]

# Base-Types
BASE_TYPE_SIZE = {
    0x00: 1, 0x01: 1, 0x02: 1, 0x83: 2, 0x84: 2, 0x85: 4, 0x86: 4,
    0x07: 1, 0x88: 4, 0x89: 8, 0x0A: 1, 0x8B: 2, 0x8C: 4, 0x0D: 1,
    0x8E: 8, 0x8F: 8, 0x90: 8,
}
BASE_TYPE_FMT = {
    0x00: "B", 0x01: "b", 0x02: "B", 0x83: "h", 0x84: "H", 0x85: "i",
    0x86: "I", 0x88: "f", 0x89: "d", 0x0A: "B", 0x8B: "H", 0x8C: "I",
    0x8E: "q", 0x8F: "Q", 0x90: "Q",
}

# Ungültig-Werte (FIT-Profil)
INVALID = {1: 0xFF, 2: 0xFFFF, 4: 0xFFFFFFFF}


def _fmt(btype, size):
    """struct-Format passend zu Base-Type und tatsächlicher Feldgröße
    (die Definition kann kleinere Größen angeben als der Base-Type)."""
    if btype in (0x88, 0x89):
        return BASE_TYPE_FMT[btype]
    signed = btype in (0x01, 0x83, 0x85, 0x8E)
    if size == 1:
        return "b" if signed else "B"
    if size == 2:
        return "h" if signed else "H"
    if size == 4:
        return "i" if signed else "I"
    if size == 8:
        return "q" if signed else "Q"
    return "B"

# ---------------------------------------------------------------------------
# Minimaler FIT-Parser (Definition Messages, komprimierte Timestamps,
# Developer-Felder werden uebersprungen)
# ---------------------------------------------------------------------------


def parse_fit(path):
    """Liest eine FIT-Datei und liefert eine Liste (global_num, felder, ts)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 12 or data[8:12] != b".FIT":
        raise ValueError("%s ist keine FIT-Datei" % path)
    # Daten beginnen nach dem Header (12 oder 14 Byte, gemaess
    # Groessenfeld). Eine optionale CRC steht am Dateiende.
    header_size = data[0]
    data_size = struct.unpack("<I", data[4:8])[0]
    body = data[header_size:header_size + data_size]

    definitions = {}   # local -> (global_num, [(fnum, size, btype)])
    dev_fields = {}    # local -> [(name, size)] (Developer-Felder)
    dev_names = {}     # (dev_data_index, def_num) -> field_name
    messages = []
    last_ts = 0
    last_offset = 0
    i = 0

    def read_value(fnum, size, btype, raw):
        if btype == 0x07:  # String
            return raw.decode("utf-8", "replace").rstrip("\x00")
        if size in (1, 2, 4, 8) and btype in BASE_TYPE_FMT:
            return struct.unpack("<" + _fmt(btype, size), raw)[0]
        # Byte-Arrays und sonstige Groessen werden ignoriert
        return None

    def read_dev_values(local, values, i):
        for (name, size) in dev_fields.get(local, []):
            raw = body[i:i + size]
            i += size
            if size == 1:
                values["dev_" + name] = raw[0]
            elif size == 2:
                values["dev_" + name] = struct.unpack("<H", raw)[0]
            elif size == 4:
                values["dev_" + name] = struct.unpack("<I", raw)[0]
        return i

    while i < len(body):
        hdr = body[i]
        i += 1
        if hdr & 0x80:
            # Komprimierter Timestamp-Header (Bit 7 = 1):
            # Bits 6-5 = local msg num (0-3), Bits 4-0 = Zeitoffset (0-31).
            # Das Timestamp-Feld fehlt in den Daten.
            local = (hdr >> 5) & 0x03
            offset = hdr & 0x1F
            delta = offset - last_offset
            if delta < 0:
                delta += 32
            last_offset = offset
            last_ts += delta
            ts = last_ts
            gnum, fields = definitions.get(local, (None, []))
            if gnum is None:
                raise ValueError("Unbekannte Definition (local %d)" % local)
            values = {}
            for (fnum, size, btype) in fields:
                if fnum == 253:
                    continue
                raw = body[i:i + size]
                i += size
                values[fnum] = read_value(fnum, size, btype, raw)
            i = read_dev_values(local, values, i)
            values[253] = ts
            messages.append((gnum, values, ts))
        else:
            # Normaler Header (Bit 7 = 0): Bit 6 = Definition,
            # Bit 5 = Developer-Data-Flag, Bits 3-0 = local msg num.
            local = hdr & 0x0F
            if hdr & 0x40:
                # Definition Message
                i += 2  # reserved + Architektur
                gnum = struct.unpack("<H", body[i:i + 2])[0]
                i += 2
                nfields = body[i]
                i += 1
                fields = []
                for _ in range(nfields):
                    fields.append((body[i], body[i + 1], body[i + 2]))
                    i += 3
                definitions[local] = (gnum, fields)
                dev_fields[local] = []
                if (hdr & 0x20) and i < len(body):
                    # Developer-Data-Definition: Dev-Feld-Anzahl + -Defs
                    ndev = body[i]
                    i += 1
                    for _ in range(ndev):
                        dnum = body[i]
                        size = body[i + 1]
                        didx = body[i + 2]
                        i += 3
                        name = dev_names.get((didx, dnum), "dev%d" % dnum)
                        dev_fields[local].append((name, size))
            else:
                # Data Message
                gnum, fields = definitions.get(local, (None, []))
                if gnum is None:
                    raise ValueError("Unbekannte Definition (local %d)" % local)
                values = {}
                for (fnum, size, btype) in fields:
                    raw = body[i:i + size]
                    i += size
                    values[fnum] = read_value(fnum, size, btype, raw)
                i = read_dev_values(local, values, i)
                if gnum == 206:
                    # field_description: Dev-Feld-Namen sammeln
                    dev_names[(values.get(3), values.get(2))] = values.get(1)
                ts = values.get(253)
                if ts is not None:
                    last_ts = ts
                    last_offset = 0
                messages.append((gnum, values, ts))
    return messages


def semicircles_to_deg(sc):
    return sc * (180.0 / (2 ** 31))


def _cadence_of(r):
    """Kadenz eines Records: natives Feld 4, sonst Dev-Feld mst_cadence."""
    v = r.get(4)
    if v is not None and v != 0xFF:
        return v
    v = r.get("dev_mst_cadence")
    if v is not None and v != 0xFF:
        return v
    return None


def haversine_m(lat1, lon1, lat2, lon2):
    import math
    r = 6371000.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(min(1.0, a)))


# ---------------------------------------------------------------------------
# Minimaler FIT-Writer (nur was wir brauchen)
# ---------------------------------------------------------------------------

def _crc16(data):
    # CRC-16/ARC (poly 0xA001 reflektiert, init 0) — der FIT-Standard.
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc & 0xFFFF


def _def(local, gnum, fields):
    # Normaler Header (Bit 7 = 0), Definition-Flag (Bit 6) gesetzt.
    # Kein Developer-Data-Flag, keine Dev-Felder.
    out = bytes([0x40 | local, 0, 0, gnum & 0xFF, (gnum >> 8) & 0xFF, len(fields)])
    for (fnum, size, btype) in fields:
        out += bytes([fnum, size, btype])
    return out


def _data(local, payload):
    # Normaler Header (Bit 7 = 0, kein Definition-Flag).
    return bytes([local]) + payload


def _pack(btype, value):
    return struct.pack("<" + BASE_TYPE_FMT[btype], value)


def _inv(size):
    return INVALID.get(size, 0)


def write_fit(path, legs, session_info):
    """Schreibt die Multisport-FIT-Datei. legs = Liste von Dicts."""
    out = bytearray()

    # Definitionen
    out += _def(0, MSG_FILE_ID, [(0, 1, 0x00), (1, 2, 0x84), (2, 2, 0x84),
                                 (3, 4, 0x8C), (4, 4, 0x86)])
    # Feldnummern nach aktuellem FIT-Profil (Session: start_time=2,
    # sport=5; Lap: avg_speed=13, sub_sport=39).
    out += _def(1, MSG_SESSION, [(253, 4, 0x86), (0, 1, 0x00), (1, 1, 0x00),
                                 (2, 4, 0x86), (3, 4, 0x85), (4, 4, 0x85),
                                 (5, 1, 0x00), (6, 1, 0x00), (7, 4, 0x86),
                                 (8, 4, 0x86), (9, 4, 0x86), (14, 2, 0x84),
                                 (15, 2, 0x84), (16, 1, 0x02), (17, 1, 0x02),
                                 (254, 2, 0x84)])
    out += _def(2, MSG_LAP, [(253, 4, 0x86), (2, 4, 0x86), (3, 4, 0x85),
                             (4, 4, 0x85), (5, 4, 0x85), (6, 4, 0x85),
                             (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86),
                             (13, 2, 0x84), (14, 2, 0x84), (15, 1, 0x02),
                             (16, 1, 0x02), (25, 1, 0x00), (39, 1, 0x00),
                             (254, 2, 0x84)])
    out += _def(3, MSG_RECORD, [(253, 4, 0x86), (0, 4, 0x85), (1, 4, 0x85),
                                (3, 1, 0x02), (4, 1, 0x02), (5, 4, 0x86),
                                (6, 2, 0x84)])
    out += _def(4, MSG_EVENT, [(253, 4, 0x86), (0, 1, 0x00), (1, 1, 0x00),
                               (2, 2, 0x84), (4, 1, 0x02)])
    out += _def(5, MSG_ACTIVITY, [(253, 4, 0x86), (0, 4, 0x86), (1, 2, 0x84)])

    first_ts = legs[0]["start"]
    total_timer = sum(l["timer"] for l in legs)

    # file_id
    out += _data(0, _pack(0x00, 4) + _pack(0x84, 1) + _pack(0x84, 3139) +
                 _pack(0x8C, 0xFFFFFFFF) + _pack(0x86, first_ts))

    # Timer-Events an den Phasengrenzen
    def evt(ts, etype):
        return _data(4, _pack(0x86, ts) + _pack(0x00, 0) + _pack(0x00, etype) +
                       _pack(0x84, 0) + _pack(0x02, 0))

    out += evt(first_ts, 0)  # start

    for idx, leg in enumerate(legs):
        sport, subsport = LEG_PROFILES[min(idx, len(LEG_PROFILES) - 1)]
        evtype = 0 if idx == 0 else 1  # session event_type: start / stop
        out += _data(1,
            _pack(0x86, leg["end"]) +
            _pack(0x00, 0) + _pack(0x00, evtype) +
            _pack(0x86, leg["start"]) +
            _pack(0x85, leg["start_lat"] if leg["start_lat"] is not None else _inv(4)) +
            _pack(0x85, leg["start_lon"] if leg["start_lon"] is not None else _inv(4)) +
            _pack(0x00, sport) + _pack(0x00, subsport) +
            _pack(0x86, int(leg["elapsed"] * 1000)) +
            _pack(0x86, int(leg["timer"] * 1000)) +
            _pack(0x86, int(leg["distance"] * 100)) +
            _pack(0x84, int(min(leg["avg_speed"], 65.534) * 1000)) +
            _pack(0x84, int(min(leg["max_speed"], 65.534) * 1000)) +
            _pack(0x02, leg["avg_hr"] if leg["avg_hr"] else 0xFF) +
            _pack(0x02, leg["max_hr"] if leg["max_hr"] else 0xFF) +
            _pack(0x84, idx))
        out += _data(2,
            _pack(0x86, leg["end"]) +
            _pack(0x86, leg["start"]) +
            _pack(0x85, leg["start_lat"] if leg["start_lat"] is not None else _inv(4)) +
            _pack(0x85, leg["start_lon"] if leg["start_lon"] is not None else _inv(4)) +
            _pack(0x85, leg["end_lat"] if leg["end_lat"] is not None else _inv(4)) +
            _pack(0x85, leg["end_lon"] if leg["end_lon"] is not None else _inv(4)) +
            _pack(0x86, int(leg["elapsed"] * 1000)) +
            _pack(0x86, int(leg["timer"] * 1000)) +
            _pack(0x86, int(leg["distance"] * 100)) +
            _pack(0x84, int(min(leg["avg_speed"], 65.534) * 1000)) +
            _pack(0x84, int(min(leg["max_speed"], 65.534) * 1000)) +
            _pack(0x02, leg["avg_hr"] if leg["avg_hr"] else 0xFF) +
            _pack(0x02, leg["max_hr"] if leg["max_hr"] else 0xFF) +
            _pack(0x00, sport) + _pack(0x00, subsport) +
            _pack(0x84, idx))
        if idx > 0:
            out += evt(leg["start"], 4)   # stop_all (Uebergang)
            out += evt(leg["start"], 0)   # start
        for rec in leg["records"]:
            out += _data(3,
                _pack(0x86, rec["ts"]) +
                _pack(0x85, rec["lat"] if rec["lat"] is not None else _inv(4)) +
                _pack(0x85, rec["lon"] if rec["lon"] is not None else _inv(4)) +
                _pack(0x02, rec["hr"] if rec["hr"] else 0xFF) +
                _pack(0x02, rec["cadence"] if rec["cadence"] else 0xFF) +
                _pack(0x86, int(rec["distance"] * 100)) +
                _pack(0x84, int(min(rec["speed"], 65.534) * 1000)))

    out += _data(5, _pack(0x86, legs[-1]["end"]) +
                 _pack(0x86, int(total_timer * 1000)) +
                 _pack(0x84, len(legs)))

    # FIT-Layout: 12-Byte-Header, dann Header-CRC (Header-Groesse 14),
    # dann Daten, dann Datei-CRC (ueber alles davor).
    header12 = struct.pack("<BBHI4s", 14, 0x20, 2165, len(out), b".FIT")
    hdr_crc = _crc16(header12)
    body_bytes = bytes(out)
    file_crc = _crc16(header12 + struct.pack("<H", hdr_crc) + body_bytes)
    with open(path, "wb") as fh:
        fh.write(header12 + struct.pack("<H", hdr_crc) + body_bytes +
                 struct.pack("<H", file_crc))


# ---------------------------------------------------------------------------
# Konvertierung
# ---------------------------------------------------------------------------


def convert(src, dst):
    msgs = parse_fit(src)

    records = [v for (g, v, ts) in msgs if g == MSG_RECORD and v.get(253) is not None]
    if not records:
        raise ValueError("Keine Record-Messages in %s gefunden" % src)
    records.sort(key=lambda v: v[253])

    laps = sorted(v.get(2) for (g, v, ts) in msgs
                  if g == MSG_LAP and v.get(2) is not None)
    if not laps:
        laps = [records[0][253]]
    if laps[0] > records[0][253]:
        laps[0] = records[0][253]

    # Records in Phasen aufteilen (Grenzen = Runden-Startzeiten)
    legs = []
    n = len(laps)
    for k in range(n):
        start = laps[k]
        end = laps[k + 1] if k + 1 < n else records[-1][253] + 1
        legs.append([r for r in records if start <= r[253] < end])
    legs = [l for l in legs if l]
    if len(legs) > len(LEG_PROFILES):
        print("Warnung: %d Runden gefunden (erwartet max. 5) — überzählige werden als Laufen gewertet."
              % len(legs))

    out_legs = []
    for k, recs in enumerate(legs):
        sport, subsport = LEG_PROFILES[min(k, len(LEG_PROFILES) - 1)]
        start = recs[0][253]
        end = recs[-1][253]
        elapsed = max(end - start, 1)

        # Distanz: kumulatives Distanzfeld, sonst Haversine
        if all(r.get(5) is not None for r in recs):
            leg_distance = (recs[-1][5] - recs[0][5]) / 100.0
            per_leg = [r[5] - recs[0][5] for r in recs]  # Rohwert-Offset (x100)
        else:
            cum = 0.0
            raw = []
            prev = None
            for r in recs:
                lat = r.get(0)
                lon = r.get(1)
                if prev is not None and lat is not None and lon is not None:
                    cum += haversine_m(prev[0], prev[1],
                                       semicircles_to_deg(lat),
                                       semicircles_to_deg(lon))
                if lat is not None and lon is not None:
                    prev = (semicircles_to_deg(lat), semicircles_to_deg(lon))
                raw.append(int(cum * 100))
            leg_distance = cum
            per_leg = raw

        # Geschwindigkeit: Feld 6, sonst aus Distanzdeltas
        speeds = []
        for i, r in enumerate(recs):
            if r.get(6) is not None:
                speeds.append(r[6] / 1000.0)
            else:
                d1 = per_leg[max(i - 1, 0)] / 100.0
                d2 = per_leg[i] / 100.0
                t1 = recs[max(i - 1, 0)][253]
                t2 = r[253]
                speeds.append((d2 - d1) / max(t2 - t1, 1))
        avg_speed = leg_distance / max(elapsed, 1)
        max_speed = max(speeds) if speeds else 0.0

        hrs = [r[3] for r in recs if r.get(3) is not None and r[3] != 0xFF]
        avg_hr = int(round(sum(hrs) / len(hrs))) if hrs else None
        max_hr = max(hrs) if hrs else None

        def first_ll(field):
            for r in recs:
                if r.get(field) is not None and r[field] != _inv(4):
                    return r[field]
            return None

        out_legs.append({
            "start": start,
            "end": end,
            "elapsed": elapsed,
            "timer": elapsed,
            "distance": leg_distance,
            "avg_speed": avg_speed,
            "max_speed": max_speed,
            "avg_hr": avg_hr,
            "max_hr": max_hr,
            "start_lat": first_ll(0),
            "start_lon": first_ll(1),
            "end_lat": None,
            "end_lon": None,
            "records": [{
                "ts": r[253],
                "lat": r.get(0) if r.get(0) != _inv(4) else None,
                "lon": r.get(1) if r.get(1) != _inv(4) else None,
                "hr": r.get(3) if r.get(3) != 0xFF else None,
                "cadence": _cadence_of(r),
                "distance": per_leg[i] / 100.0,
                "speed": speeds[i],
            } for i, r in enumerate(recs)],
        })
        # Endposition der Runde = letzte gueltige Position
        for r in reversed(recs):
            if r.get(0) is not None and r[0] != _inv(4):
                out_legs[-1]["end_lat"] = r[0]
                out_legs[-1]["end_lon"] = r[1]
                break

    write_fit(dst, out_legs, {})

    print("Multisport-FIT geschrieben: %s" % dst)
    for k, leg in enumerate(out_legs):
        name = LEG_NAMES[min(k, len(LEG_NAMES) - 1)]
        mins = leg["elapsed"] // 60
        secs = leg["elapsed"] % 60
        print("  %-10s %02d:%02d  %.2f km  HF Ø %s" % (
            name, mins, secs, leg["distance"] / 1000.0,
            str(leg["avg_hr"]) if leg["avg_hr"] else "-"))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else (
        src[:-4] + "_multisport.fit" if src.lower().endswith(".fit") else src + "_multisport.fit")
    convert(src, dst)


if __name__ == "__main__":
    main()
