using Glance;

WheelColumn minutes_at (int v) {
    var w = new WheelColumn ("Minutes", 59);
    w.select (v);
    return w;
}

void add_picker_tests () {
    Test.add_func ("/wheel/wraps", () => {
        var w = minutes_at (59);
        w.user_step (1);
        assert_cmpint (w.value, CompareOperator.EQ, 0);
        w.user_step (-1);
        assert_cmpint (w.value, CompareOperator.EQ, 59);
        var h = new WheelColumn ("Hours", 23);
        h.user_step (-1);
        assert_cmpint (h.value, CompareOperator.EQ, 23);
    });

    Test.add_func ("/wheel/signals-user-input-only", () => {
        var w = minutes_at (10);
        int changes = 0;
        w.changed.connect (() => changes++);
        w.select (30);
        assert_cmpint (changes, CompareOperator.EQ, 0);
        w.user_step (1);
        w.scroll_by (1.0, Gdk.ScrollUnit.WHEEL);
        assert_cmpint (changes, CompareOperator.EQ, 2);
    });

    Test.add_func ("/wheel/notch-direction", () => {
        // Scrolling up (negative dy) increases, like a spin button.
        var w = minutes_at (10);
        w.scroll_by (-1.0, Gdk.ScrollUnit.WHEEL);
        assert_cmpint (w.value, CompareOperator.EQ, 11);
        w.scroll_by (1.0, Gdk.ScrollUnit.WHEEL);
        w.scroll_by (1.0, Gdk.ScrollUnit.WHEEL);
        assert_cmpint (w.value, CompareOperator.EQ, 9);
    });

    Test.add_func ("/wheel/high-resolution-wheel-adds-up", () => {
        var w = minutes_at (10);
        for (int i = 0; i < 7; i++) w.scroll_by (-0.125, Gdk.ScrollUnit.WHEEL);
        assert_cmpint (w.value, CompareOperator.EQ, 10);
        w.scroll_by (-0.125, Gdk.ScrollUnit.WHEEL);
        assert_cmpint (w.value, CompareOperator.EQ, 11);
    });

    Test.add_func ("/wheel/direction-change-drops-leftover", () => {
        var w = minutes_at (10);
        w.scroll_by (-0.6, Gdk.ScrollUnit.WHEEL);
        w.scroll_by (0.6, Gdk.ScrollUnit.WHEEL);
        w.scroll_by (-0.6, Gdk.ScrollUnit.WHEEL);
        assert_cmpint (w.value, CompareOperator.EQ, 10);
    });

    Test.add_func ("/wheel/touchpad", () => {
        var w = minutes_at (10);
        // Small jitter never steps.
        w.scroll_by (-3, Gdk.ScrollUnit.SURFACE);
        w.scroll_by (3, Gdk.ScrollUnit.SURFACE);
        w.scroll_by (-3, Gdk.ScrollUnit.SURFACE);
        assert_cmpint (w.value, CompareOperator.EQ, 10);
        // The same travel steps the same amount whether it arrives in one event or many small ones.
        w.scroll_by (-200, Gdk.ScrollUnit.SURFACE);
        assert_true (w.value > 10);
        var fine = minutes_at (10);
        for (int i = 0; i < 200; i++) fine.scroll_by (-1, Gdk.ScrollUnit.SURFACE);
        assert_cmpint (fine.value, CompareOperator.EQ, w.value);
    });

    Test.add_func ("/wheel/typed-overflow", () => {
        var w = minutes_at (75);
        assert_cmpint (w.value, CompareOperator.EQ, 75);
        w.user_step (-1);
        assert_cmpint (w.value, CompareOperator.EQ, 58);
        w.select (75);
        w.user_step (1);
        assert_cmpint (w.value, CompareOperator.EQ, 0);
        w.select (500);
        assert_cmpint (w.value, CompareOperator.EQ, 99);
    });

    Test.add_func ("/picker/duration", () => {
        var p = new DurationPicker ();
        int changes = 0;
        p.changed.connect (() => changes++);
        p.set_fields (1, 2, 3);
        assert_true (p.duration == Duration.HOUR + 2 * Duration.MINUTE + 3 * Duration.SECOND);
        p.seconds.user_step (1);
        assert_cmpint (changes, CompareOperator.EQ, 1);
        assert_true (p.duration == Duration.HOUR + 2 * Duration.MINUTE + 4 * Duration.SECOND);
    });
}

int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("1..0 # SKIP no display\n");
        return 0;
    }
    Test.init (ref args);
    add_picker_tests ();
    return Test.run ();
}
