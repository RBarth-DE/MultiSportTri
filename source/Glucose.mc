//! CGM (glucose) display via the AAPS Garmin plugin on the phone.
//!
//! The plugin runs a small HTTP server on the phone (default port 28891,
//! reached through the Garmin Connect proxy via 127.0.0.1). The /get
//! endpoint returns the glucose history as "encodedGlucose": Base64 of
//! delta + zigzag + varint encoded (timestampSec, glucoseMgDl) pairs,
//! designed specifically for watches with little memory. The last pair is
//! the latest reading.

import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

const GLUCOSE_URL = "http://127.0.0.1:28891/get";
//! 1 mg/dl in mmol/l.
const MMOL_PER_MGDL = 0.055506;

const BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

//! Glucose manager singleton (pattern follows the known-good AAPS widget).
var glucose as GlucoseMgr = new GlucoseMgr();

class GlucoseMgr {

    //! Latest reading in the plugin's unit ("mmol" or "mgdl").
    var value as Float or Null = null;
    //! Second-to-last reading (mgdl), for the trend sign.
    var prevMgDl as Number = 0;
    var unit as String = "mmol";
    var timestampSec as Number = 0;
    var connected as Boolean = false;
    var fetching as Boolean = false;

    function initialize() {
    }

    //! Request the latest glucose reading from the AAPS plugin.
    function fetch() as Void {
        if (fetching) {
            return;
        }
        fetching = true;
        Communications.makeWebRequest(
            GLUCOSE_URL,
            {},
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            method(:onResponse)
        );
    }

    //! Response callback of fetch().
    //! @param responseCode HTTP status or BLE error code
    //! @param data Parsed JSON body
    function onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        fetching = false;
        if (responseCode == 200 && data instanceof Dictionary) {
            var dict = data as Dictionary;
            var enc = dict["encodedGlucose"];
            if (enc != null) {
                var decoded = decodeGlucose(enc as String);
                if (decoded != null) {
                    timestampSec = decoded[0];
                    prevMgDl = decoded[1];
                    value = decoded[2].toFloat();
                    var u = dict["glucoseUnit"];
                    if (u != null) {
                        unit = u as String;
                    }
                    var c = dict["connected"];
                    connected = c != null ? c as Boolean : true;
                    WatchUi.requestUpdate();
                    return;
                }
            }
        }
        // Request failed: keep the last value, mark the connection lost.
        connected = false;
        WatchUi.requestUpdate();
    }

    //! Compact value text for a data field, in the plugin's own unit
    //! ("mgdl" or "mmoll"): the encoded values always arrive in mg/dl,
    //! so they are only converted for mmol users.
    //! @return Formatted glucose text
    function valueText() as String {
        if (value == null) {
            return connected ? "…" : "--";
        }
        var trend = "=";
        var delta = value - prevMgDl;
        if (delta > 0) {
            trend = "+";
        } else if (delta < 0) {
            trend = "-";
        }
        if (unit.equals("mgdl")) {
            return value.toNumber().format("%d") + " " + trend;
        }
        return (value * MMOL_PER_MGDL).format("%.1f") + " " + trend;
    }

    //! Display color: green in range, red low, amber high, gray stale/offline.
    //! @return Color value
    function color() as Number {
        if (value == null) {
            return Graphics.COLOR_LT_GRAY;
        }
        if (Time.now().value() - timestampSec > 900) {
            return Graphics.COLOR_DK_GRAY; // stale (>15 min)
        }
        if (unit.equals("mgdl")) {
            if (value < 70.0) {
                return 0xFF5252; // red: low
            }
            if (value > 180.0) {
                return 0xFFB300; // amber: high
            }
        } else {
            var mmol = value * MMOL_PER_MGDL;
            if (mmol < 3.9) {
                return 0xFF5252; // red: low
            }
            if (mmol > 10.0) {
                return 0xFFB300; // amber: high
            }
        }
        return Graphics.COLOR_GREEN;
    }
}

//! Decode the delta/zigzag/varint encoded glucose list.
//! @param enc Base64 encoded data
//! @return [lastTimestampSec, previousGlucoseMgDl, lastGlucoseMgDl], or null
function decodeGlucose(enc as String) as [Number, Number, Number] or Null {
    var bytes = base64Decode(enc);
    if (bytes.size() < 2) {
        return null;
    }
    var pos = 0;
    var timeSec = 0;
    var glucoseMgDl = 0;
    var prevGlucose = 0;
    var count = 0;
    while (pos < bytes.size()) {
        var t = readVarInt(bytes, pos);
        pos = t[1];
        var g = readVarInt(bytes, pos);
        pos = g[1];
        prevGlucose = glucoseMgDl;
        timeSec = timeSec + zigzagDecode(t[0]);
        glucoseMgDl = glucoseMgDl + zigzagDecode(g[0]);
        count = count + 1;
    }
    if (count < 1) {
        return null;
    }
    if (count < 2) {
        prevGlucose = glucoseMgDl;
    }
    return [timeSec, prevGlucose, glucoseMgDl];
}

//! Unsigned LEB128 varint decode.
//! @param bytes Byte buffer
//! @param pos Start position
//! @return [value, nextPosition]
function readVarInt(bytes as Array<Number>, pos as Number) as [Number, Number] {
    var result = 0;
    var shift = 0;
    while (pos < bytes.size()) {
        var b = bytes[pos];
        pos = pos + 1;
        result = result | ((b & 0x7F) << shift);
        if ((b & 0x80) == 0) {
            break;
        }
        shift = shift + 7;
        if (shift > 28) {
            break;
        }
    }
    return [result, pos];
}

//! Zigzag decode (maps unsigned varints to signed values).
//! @param u Unsigned value
//! @return Signed value
function zigzagDecode(u as Number) as Number {
    return (u / 2) ^ (-(u % 2));
}

//! Minimal Base64 decoder (the Connect IQ API has none).
//! @param enc Base64 string
//! @return Decoded bytes
function base64Decode(enc as String) as Array<Number> {
    var result = new Array<Number>[0];
    var buffer = 0;
    var bits = 0;
    for (var i = 0; i < enc.length(); i++) {
        var c = enc.substring(i, i + 1);
        if (c.equals("=")) {
            break;
        }
        var v = BASE64_CHARS.find(c);
        if (v < 0) {
            continue;
        }
        buffer = (buffer << 6) | v;
        bits = bits + 6;
        if (bits >= 8) {
            bits = bits - 8;
            result.add((buffer >> bits) & 0xFF);
            if (bits > 0) {
                buffer = buffer & ((1 << bits) - 1);
            } else {
                buffer = 0;
            }
        }
    }
    return result;
}
