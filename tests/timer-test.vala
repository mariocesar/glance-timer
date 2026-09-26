using Glance;

const int64 S = Duration.SECOND;

class FakeClock {
    public int64 mono = 5000 * S;
    public int64 wall = 1790000000 * S;
}

Glance.Timer make_timer (FakeClock c) {
    var t = new Glance.Timer ();
    t.now = () => c.mono;
    t.real_now = () => c.wall;
    return t;
}

void add_timer_tests () {
    Test.add_func ("/timer/initial-idle", () => {
        var t = make_timer (new FakeClock ());
        assert_true (t.state == TimerState.IDLE);
        assert_cmpint ((int) t.remaining, CompareOperator.EQ, 0);
        assert_cmpfloat (t.progress, CompareOperator.EQ, 0.0);
    });

    Test.add_func ("/timer/reject-zero-negative-and-over-max", () => {
        var t = make_timer (new FakeClock ());
        assert_false (t.start (0));
        assert_false (t.start (-S));
        assert_false (t.start (Duration.MAX + 1));
        assert_true (t.state == TimerState.IDLE);
    });

    Test.add_func ("/timer/one-second", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        assert_true (t.start (S));
        assert_true (t.state == TimerState.RUNNING);
        assert_true (t.remaining == S);
        c.mono += S - 1;
        t.check ();
        assert_true (t.state == TimerState.RUNNING);
        c.mono += 1;
        t.check ();
        assert_true (t.state == TimerState.FINISHED);
    });

    Test.add_func ("/timer/maximum-duration", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        assert_true (t.start (Duration.MAX));
        assert_true (t.remaining == Duration.MAX);
        assert_cmpstr (Duration.format (t.remaining), CompareOperator.EQ, "23:59:59");
    });

    Test.add_func ("/timer/pause-resume-stop", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        assert_false (t.pause ());
        assert_false (t.resume ());
        t.start (10 * S);
        assert_false (t.resume ());
        c.mono += 3 * S;
        assert_true (t.pause ());
        assert_true (t.state == TimerState.PAUSED);
        assert_true (t.remaining == 7 * S);
        assert_false (t.pause ());
        assert_true (t.resume ());
        assert_true (t.state == TimerState.RUNNING);
        t.stop ();
        assert_true (t.state == TimerState.IDLE);
        assert_true (t.remaining == 0);
        assert_true (t.total == 0);
    });

    Test.add_func ("/timer/pause-excludes-paused-time", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        t.start (10 * S);
        c.mono += 4 * S;
        t.pause ();
        c.mono += 3600 * S;
        t.check ();
        assert_true (t.state == TimerState.PAUSED);
        assert_true (t.remaining == 6 * S);
        t.resume ();
        c.mono += 5 * S;
        assert_true (t.remaining == S);
    });

    Test.add_func ("/timer/finishes-exactly-once", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        int count = 0;
        t.finished.connect (() => count++);
        t.start (2 * S);
        c.mono += 5 * S;
        t.check ();
        t.check ();
        c.mono += 5 * S;
        t.check ();
        assert_cmpint (count, CompareOperator.EQ, 1);
        assert_true (t.state == TimerState.FINISHED);
        assert_true (t.remaining == 0);
        assert_cmpfloat (t.progress, CompareOperator.EQ, 1.0);
        assert_false (t.pause ());
        assert_false (t.add (S));
    });

    Test.add_func ("/timer/late-tick-does-not-drift", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        t.start (10 * S);
        // No checks for 7.3 s, as if the UI stalled: the deadline is unaffected.
        c.mono += 7300000;
        t.check ();
        assert_true (t.remaining == 2700000);
        c.mono += 2700000;
        t.check ();
        assert_true (t.state == TimerState.FINISHED);
    });

    Test.add_func ("/timer/restart-replaces", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        t.start (10 * S);
        c.mono += 4 * S;
        assert_true (t.start (60 * S));
        assert_true (t.remaining == 60 * S);
        assert_true (t.total == 60 * S);
    });

    Test.add_func ("/timer/add-while-running", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        t.start (60 * S);
        c.mono += 30 * S;
        assert_true (t.add (5 * Duration.MINUTE));
        assert_true (t.remaining == 330 * S);
        assert_true (t.total == 360 * S);
        assert_cmpfloat_with_epsilon (t.progress, 30.0 / 360.0, 1e-9);
    });

    Test.add_func ("/timer/add-while-paused", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        t.start (60 * S);
        c.mono += 20 * S;
        t.pause ();
        assert_true (t.add (30 * S));
        assert_true (t.state == TimerState.PAUSED);
        assert_true (t.remaining == 70 * S);
        t.resume ();
        c.mono += 70 * S;
        t.check ();
        assert_true (t.state == TimerState.FINISHED);
    });

    Test.add_func ("/timer/add-caps-and-rejects", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        assert_false (t.add (S));
        t.start (Duration.MAX - 10 * S);
        assert_false (t.add (0));
        assert_false (t.add (-S));
        assert_true (t.add (Duration.HOUR));
        assert_true (t.remaining == Duration.MAX);
        assert_true (t.progress >= 0.0 && t.progress <= 1.0);
        // Adding after time has passed keeps total within the cap, so a restart still works.
        c.mono += 60 * S;
        assert_true (t.add (Duration.HOUR));
        assert_true (t.total == Duration.MAX);
        assert_true (t.start (t.total));
    });

    Test.add_func ("/timer/duration-ignores-wall-clock", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        t.start (60 * S);
        c.wall += 3600 * S;
        c.wall -= 7200 * S;
        assert_true (t.remaining == 60 * S);
    });

    Test.add_func ("/timer/until-follows-wall-clock", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        assert_false (t.start_until (c.wall));
        assert_false (t.start_until (c.wall - S));
        assert_true (t.start_until (c.wall + 600 * S));
        assert_true (t.is_until);
        c.mono += 300 * S;
        assert_true (t.remaining == 600 * S);
        c.wall += 100 * S;
        assert_true (t.remaining == 500 * S);
        assert_false (t.pause ());
        assert_true (t.add (60 * S));
        assert_true (t.remaining == 560 * S);
        // A backward clock jump adds time but never makes progress negative.
        c.wall -= 1000 * S;
        assert_true (t.remaining == 1560 * S);
        assert_true (t.progress == 0.0);
        c.wall += 1000 * S;
        // A forward clock jump past the target finishes it.
        c.wall += 3600 * S;
        t.check ();
        assert_true (t.state == TimerState.FINISHED);
        t.stop ();
        assert_false (t.is_until);
    });

    Test.add_func ("/timer/tick-signal", () => {
        var c = new FakeClock ();
        var t = make_timer (c);
        int ticks = 0;
        t.tick.connect (() => ticks++);
        t.start (10 * S);
        t.pause ();
        t.resume ();
        t.add (S);
        t.stop ();
        assert_cmpint (ticks, CompareOperator.EQ, 5);
    });

    Test.add_func ("/timer/tick-interval", () => {
        // Next change of the displayed second, plus 1 ms slack.
        assert_cmpuint (Glance.Timer.tick_interval (1500 * S), CompareOperator.EQ, 1001);
        assert_cmpuint (Glance.Timer.tick_interval (1500 * S + 1), CompareOperator.EQ, 2);
        assert_cmpuint (Glance.Timer.tick_interval (1500000), CompareOperator.EQ, 501);
        assert_cmpuint (Glance.Timer.tick_interval (1), CompareOperator.EQ, 2);
        assert_cmpuint (Glance.Timer.tick_interval (0), CompareOperator.EQ, 1);
    });

    Test.add_func ("/timer/owned-tick-finishes-without-ui", () => {
        // Real clocks and main loop: the timer finishes on its own.
        var t = new Glance.Timer ();
        var loop = new MainLoop ();
        int count = 0;
        t.finished.connect (() => { count++; loop.quit (); });
        t.start (50000);
        var guard = Timeout.add (2000, () => { loop.quit (); return Source.REMOVE; });
        loop.run ();
        Source.remove (guard);
        assert_cmpint (count, CompareOperator.EQ, 1);
        assert_true (t.state == TimerState.FINISHED);
    });
}

void add_clock_tests () {
    Test.add_func ("/clock/boottime-never-behind-monotonic", () => {
        var mono = get_monotonic_time ();
        var boot = boottime ();
        assert_true (boot >= mono);
        assert_true (boottime () >= boot);
    });
}

void add_format_tests () {
    Test.add_func ("/format/below-one-hour", () => {
        assert_cmpstr (Duration.format (0), CompareOperator.EQ, "00:00");
        assert_cmpstr (Duration.format (1), CompareOperator.EQ, "00:01");
        assert_cmpstr (Duration.format (5 * S), CompareOperator.EQ, "00:05");
        assert_cmpstr (Duration.format (59200000), CompareOperator.EQ, "01:00");
        assert_cmpstr (Duration.format (25 * Duration.MINUTE), CompareOperator.EQ, "25:00");
        assert_cmpstr (Duration.format (Duration.HOUR - S), CompareOperator.EQ, "59:59");
    });

    Test.add_func ("/format/one-hour-and-above", () => {
        assert_cmpstr (Duration.format (Duration.HOUR), CompareOperator.EQ, "01:00:00");
        assert_cmpstr (Duration.format (Duration.HOUR - 1), CompareOperator.EQ, "01:00:00");
        assert_cmpstr (Duration.format (Duration.HOUR + 11 * Duration.MINUTE + 48 * S), CompareOperator.EQ, "01:11:48");
        assert_cmpstr (Duration.format (Duration.MAX), CompareOperator.EQ, "23:59:59");
    });
}

int main (string[] args) {
    Test.init (ref args);
    add_timer_tests ();
    add_format_tests ();
    add_clock_tests ();
    return Test.run ();
}
