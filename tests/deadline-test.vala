using Glance;

TimeZone zone (string id) {
    try {
        return new TimeZone.identifier (id);
    } catch (Error e) {
        error ("missing tzdata for %s", id);
    }
}

TimeZone madrid () { return zone ("Europe/Madrid"); }
TimeZone ny () { return zone ("America/New_York"); }

string resolved (string text, DateTime now) {
    var target = Deadline.resolve (text, now);
    return target == null ? "null" : target.format ("%F %H:%M %Z");
}

void add_deadline_tests () {
    Test.add_func ("/deadline/future-today", () => {
        var now = new DateTime (madrid (), 2026, 9, 26, 10, 15, 30);
        assert_cmpstr (resolved ("14:30", now), CompareOperator.EQ, "2026-09-26 14:30 CEST");
        assert_cmpstr (resolved ("9:05", new DateTime (madrid (), 2026, 9, 26, 8, 0, 0)), CompareOperator.EQ, "2026-09-26 09:05 CEST");
        assert_cmpstr (resolved ("10:16", now), CompareOperator.EQ, "2026-09-26 10:16 CEST");
    });

    Test.add_func ("/deadline/passed-rolls-to-tomorrow", () => {
        var now = new DateTime (madrid (), 2026, 9, 26, 15, 0, 0);
        assert_cmpstr (resolved ("14:30", now), CompareOperator.EQ, "2026-09-27 14:30 CEST");
        // Exactly now, and earlier within the same minute, are not in the future.
        assert_cmpstr (resolved ("15:00", now), CompareOperator.EQ, "2026-09-27 15:00 CEST");
        assert_cmpstr (resolved ("15:00", new DateTime (madrid (), 2026, 9, 26, 15, 0, 30)), CompareOperator.EQ, "2026-09-27 15:00 CEST");
    });

    Test.add_func ("/deadline/midnight", () => {
        var late = new DateTime (madrid (), 2026, 12, 31, 23, 50, 0);
        assert_cmpstr (resolved ("00:00", late), CompareOperator.EQ, "2027-01-01 00:00 CET");
        assert_cmpstr (resolved ("0:10", late), CompareOperator.EQ, "2027-01-01 00:10 CET");
        assert_cmpstr (resolved ("23:59", new DateTime (madrid (), 2026, 9, 26, 0, 5, 0)), CompareOperator.EQ, "2026-09-26 23:59 CEST");
        var target = Deadline.resolve ("00:00", late);
        assert_true (target.difference (late) == 10 * Duration.MINUTE);
    });

    Test.add_func ("/deadline/dst", () => {
        // Spring forward: 02:30 does not exist and moves to the end of the gap.
        assert_cmpstr (resolved ("2:30", new DateTime (ny (), 2026, 3, 8, 1, 0, 0)), CompareOperator.EQ, "2026-03-08 03:00 EDT");
        // Rolling to tomorrow over a DST change keeps the wall-clock time, not +24 h.
        var before = new DateTime (ny (), 2026, 3, 7, 12, 0, 0);
        var target = Deadline.resolve ("9:00", before);
        assert_cmpstr (target.format ("%F %H:%M %Z"), CompareOperator.EQ, "2026-03-08 09:00 EDT");
        assert_true (target.difference (before) == 20 * Duration.HOUR);
        // Fall back: 01:30 happens twice; GLib picks the standard-time occurrence.
        assert_cmpstr (resolved ("1:30", new DateTime (ny (), 2026, 11, 1, 0, 30, 0)), CompareOperator.EQ, "2026-11-01 01:30 EST");
    });

    Test.add_func ("/deadline/malformed", () => {
        var now = new DateTime (madrid (), 2026, 9, 26, 10, 0, 0);
        string[] bad = { "", "14", "14:3", "14:300", "24:00", "12:60", "123:00", "-1:00", "1a:00", "14:30:00", "2:30pm", " : ", "14.30" };
        foreach (var text in bad) {
            if (Deadline.resolve (text, now) != null) Test.message ("accepted: '%s'", text);
            assert_null (Deadline.resolve (text, now));
        }
        assert_cmpstr (resolved (" 14:30 ", now), CompareOperator.EQ, "2026-09-26 14:30 CEST");
    });

    Test.add_func ("/deadline/describe", () => {
        var now = new DateTime (madrid (), 2026, 9, 26, 15, 0, 0);
        assert_cmpstr (Deadline.describe (Deadline.resolve ("17:15", now), now), CompareOperator.EQ, "17:15");
        assert_cmpstr (Deadline.describe (Deadline.resolve ("09:05", now), now), CompareOperator.EQ, "09:05 tomorrow");
        var nye = new DateTime (madrid (), 2026, 12, 31, 23, 0, 0);
        assert_cmpstr (Deadline.describe (Deadline.resolve ("00:30", nye), nye), CompareOperator.EQ, "00:30 tomorrow");
    });

    Test.add_func ("/deadline/drives-until-timer", () => {
        var now = new DateTime (madrid (), 2026, 9, 26, 14, 0, 0);
        int64 wall = now.to_unix () * Duration.SECOND;
        var t = new Glance.Timer ();
        t.real_now = () => wall;
        assert_true (t.start_until (Deadline.resolve ("14:30", now).to_unix () * Duration.SECOND));
        assert_true (t.remaining == 30 * Duration.MINUTE);
        assert_cmpstr (Duration.format (t.remaining), CompareOperator.EQ, "30:00");
        t.stop ();
    });
}

int main (string[] args) {
    Test.init (ref args);
    add_deadline_tests ();
    return Test.run ();
}
