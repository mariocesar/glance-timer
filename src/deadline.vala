// Until-mode targets: a local wall-clock time, today if still ahead, otherwise tomorrow.
namespace Glance.Deadline {
    // Parses H:MM or HH:MM (24-hour) relative to `now`. Returns null when malformed.
    public DateTime? resolve (string text, DateTime now) {
        var parts = text.strip ().split (":");
        if (parts.length != 2 || parts[0].length < 1 || parts[0].length > 2 || parts[1].length != 2) return null;
        foreach (var part in parts) {
            for (int i = 0; i < part.length; i++) {
                if (!part[i].isdigit ()) return null;
            }
        }
        var hour = int.parse (parts[0]);
        var minute = int.parse (parts[1]);
        if (hour > 23 || minute > 59) return null;

        var target = at (now, hour, minute);
        if (target.compare (now) <= 0) {
            // add_days keeps the calendar day right across DST changes, unlike adding 86400 s.
            target = at (now.add_days (1), hour, minute);
        }
        return target;
    }

    // "14:30", or "14:30 tomorrow" when the target is not on the same day as `now`.
    public string describe (DateTime target, DateTime now) {
        var time = target.format ("%H:%M");
        var same_day = target.get_year () == now.get_year () && target.get_day_of_year () == now.get_day_of_year ();
        return same_day ? time : time + " tomorrow";
    }

    DateTime at (DateTime day, int hour, int minute) {
        return new DateTime (day.get_timezone (), day.get_year (), day.get_month (), day.get_day_of_month (), hour, minute, 0);
    }
}
