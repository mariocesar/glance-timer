namespace Glance.Duration {
    public const int64 SECOND = 1000000;
    public const int64 MINUTE = 60 * SECOND;
    public const int64 HOUR = 60 * MINUTE;
    public const int64 MAX = 23 * HOUR + 59 * MINUTE + 59 * SECOND;

    // MM:SS below one hour, HH:MM:SS from one hour. Rounds up so a running timer never reads 00:00.
    public string format (int64 us) {
        var total = (int64.max (us, 0) + SECOND - 1) / SECOND;
        var h = total / 3600;
        var m = total / 60 % 60;
        var s = total % 60;
        if (h > 0) return "%02lld:%02lld:%02lld".printf (h, m, s);
        return "%02lld:%02lld".printf (m, s);
    }
}

namespace Glance.Duration {
    // Parses CLI durations such as 45s, 25m, 1h30m, 1h 2m 3s. Units in h, m, s order, each at most once;
    // spaces are allowed only after a unit.
    // Returns microseconds, or -1 when malformed. Callers reject 0 and values above MAX.
    public int64 parse (string text) {
        var s = text.strip ().down ();
        if (s == "") return -1;
        int64 total = 0;
        int number = -1;
        int digits = 0;
        int last_unit = 4;
        for (int i = 0; i < s.length; i++) {
            var c = s[i];
            if (c == ' ') {
                if (number >= 0) return -1;
                continue;
            }
            if (c.isdigit ()) {
                if (++digits > 6) return -1;
                number = (number < 0 ? 0 : number) * 10 + (c - '0');
                continue;
            }
            int unit = c == 'h' ? 3 : c == 'm' ? 2 : c == 's' ? 1 : 0;
            if (unit == 0 || number < 0 || unit >= last_unit) return -1;
            total += number * (unit == 3 ? HOUR : unit == 2 ? MINUTE : SECOND);
            last_unit = unit;
            number = -1;
            digits = 0;
        }
        return number < 0 ? total : -1;
    }
}

// Keyboard duration entry. Digits fill right-aligned as HHMMSS; each '.' closes the
// current group so it moves one unit up: 50 is 50 s, 50. is 50 min, 1.. is 1 h, 1.30 is 1:30.
public class Glance.DigitEntry {
    public string text { get; private set; default = ""; }

    // Returns false when the key is ignored (not a digit or dot, or no room left).
    public bool push (unichar c) {
        var groups = split_groups ();
        var last = groups[groups.length - 1];
        if (c == '.') {
            if (groups.length == 3 || groups[0].length > first_capacity (groups.length + 1)) return false;
        } else if (c >= '0' && c <= '9') {
            var room = groups.length == 1 ? first_capacity (1) : 2;
            if (last.length >= room) return false;
        } else {
            return false;
        }
        text += c.to_string ();
        return true;
    }

    // Removes the last typed key. Returns false when already empty.
    public bool backspace () {
        if (text == "") return false;
        text = text.substring (0, text.length - 1);
        return true;
    }

    public void clear () {
        text = "";
    }

    // Field values as typed; minutes and seconds may exceed 59 until committed.
    public void fields (out int hours, out int minutes, out int seconds) {
        int units[3] = { 0, 0, 0 };
        var groups = split_groups ();
        var first = groups[0];
        var capacity = first_capacity (groups.length);
        var padded = string.nfill (capacity - first.length, '0') + first;
        var end = 3 - groups.length;
        for (int i = 0; i < capacity / 2; i++) {
            units[end - capacity / 2 + 1 + i] = int.parse (padded.substring (i * 2, 2));
        }
        for (int g = 1; g < groups.length; g++) {
            units[end + g] = int.parse (groups[g]);
        }
        hours = units[0];
        minutes = units[1];
        seconds = units[2];
    }

    // Committed length in microseconds using h*3600 + m*60 + s.
    public int64 value () {
        int h, m, s;
        fields (out h, out m, out s);
        return h * Duration.HOUR + m * Duration.MINUTE + s * Duration.SECOND;
    }

    // g_strsplit returns no groups for "", but an empty entry is one empty group.
    string[] split_groups () {
        return text == "" ? new string[] { "" } : text.split (".");
    }

    // Digits the first group can hold when there are `groups` groups: HHMMSS, HHMM, HH.
    static int first_capacity (int groups) {
        return 6 - 2 * (groups - 1);
    }
}
