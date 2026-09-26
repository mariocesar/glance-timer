// Keyboard routing in the setup and running views, driven through the window's key controller.
using Glance;

Glance.Application app;
TimerWindow win;
Gtk.EventController keys;
int64 fake_now;

bool press (uint keyval, Gdk.ModifierType state = 0) {
    bool handled = false;
    Signal.emit_by_name (keys, "key-pressed", keyval, 0u, state, out handled);
    return handled;
}

void type (string text) {
    for (int i = 0; i < text.length; i++) {
        var c = text[i];
        press (c == '.' ? Gdk.Key.period : Gdk.Key.@0 + (c - '0'));
    }
}

Gtk.Widget? find (Gtk.Widget root, Type type, string? label = null) {
    for (var child = root.get_first_child (); child != null; child = child.get_next_sibling ()) {
        if (child.get_type ().is_a (type) && (label == null || (child is Gtk.Button && ((Gtk.Button) child).label == label))) return child;
        var found = find (child, type, label);
        if (found != null) return found;
    }
    return null;
}

void reset () {
    app.timer.stop ();
    ((Gtk.ToggleButton) find (win, typeof (Gtk.ToggleButton), "Duration")).active = true;
    press (Gdk.Key.Escape);
    win.set_focus (null);
}

void add_window_tests () {
    Test.add_func ("/keys/default-starts-25-minutes", () => {
        app.timer.stop ();
        assert_true (press (Gdk.Key.Return));
        assert_true (app.timer.state == TimerState.RUNNING);
        assert_true (app.timer.total == 25 * Duration.MINUTE);
        assert_true (press (Gdk.Key.Escape));
        assert_true (app.timer.state == TimerState.IDLE);
    });

    Test.add_func ("/keys/digits", () => {
        reset ();
        type ("12345");
        press (Gdk.Key.Return);
        assert_true (app.timer.total == Duration.HOUR + 23 * Duration.MINUTE + 45 * Duration.SECOND);
        assert_true (press (Gdk.Key.KP_Enter));
        assert_true (app.timer.state == TimerState.IDLE);
    });

    Test.add_func ("/keys/dot-and-keypad", () => {
        reset ();
        type ("50.");
        press (Gdk.Key.Return);
        assert_true (app.timer.total == 50 * Duration.MINUTE);
        reset ();
        press (Gdk.Key.KP_4);
        press (Gdk.Key.KP_5);
        press (Gdk.Key.KP_Decimal);
        press (Gdk.Key.KP_Enter);
        assert_true (app.timer.total == 45 * Duration.MINUTE);
        reset ();
        press (Gdk.Key.@1);
        press (Gdk.Key.comma);
        press (Gdk.Key.comma);
        press (Gdk.Key.Return);
        assert_true (app.timer.total == Duration.HOUR);
    });

    Test.add_func ("/keys/overflow-and-backspace", () => {
        reset ();
        type ("75");
        press (Gdk.Key.Return);
        assert_true (app.timer.total == 75 * Duration.SECOND);
        reset ();
        type ("1");
        assert_true (press (Gdk.Key.BackSpace));
        type ("2");
        press (Gdk.Key.Return);
        assert_true (app.timer.total == 2 * Duration.SECOND);
    });

    Test.add_func ("/keys/rejects-zero-and-too-long", () => {
        reset ();
        press (Gdk.Key.Return);
        assert_true (app.timer.state == TimerState.IDLE);
        type ("995959");
        press (Gdk.Key.Return);
        assert_true (app.timer.state == TimerState.IDLE);
    });

    Test.add_func ("/keys/wheel-change-restarts-typing", () => {
        reset ();
        var picker = (DurationPicker) find (win, typeof (DurationPicker));
        type ("12");
        picker.minutes.user_step (1);
        type ("3");
        press (Gdk.Key.Return);
        assert_true (app.timer.total == 3 * Duration.SECOND);
    });

    Test.add_func ("/keys/label-entry-keeps-its-keys", () => {
        reset ();
        type ("5");
        var entry = (Gtk.Entry) find (win, typeof (Gtk.Entry));
        entry.text = "Deep work";
        win.set_focus (entry);
        assert_true (win.get_focus () is Gtk.Editable);
        assert_false (press (Gdk.Key.@5));
        assert_false (press (Gdk.Key.BackSpace));
        assert_true (press (Gdk.Key.Return));
        assert_true (app.timer.state == TimerState.RUNNING);
        assert_cmpstr (app.label, CompareOperator.EQ, "Deep work");
        assert_true (app.timer.total == 5 * Duration.SECOND);
        entry.text = "";
    });

    Test.add_func ("/keys/until-mode", () => {
        reset ();
        ((Gtk.ToggleButton) find (win, typeof (Gtk.ToggleButton), "Until")).active = true;
        // A fifth digit would not fit HHMM and is dropped.
        type ("14305");
        press (Gdk.Key.Return);
        assert_true (app.timer.is_until);
        var expected = Deadline.resolve ("14:30", new DateTime.now_local ()).to_unix () * Duration.SECOND - get_real_time ();
        var diff = app.timer.remaining - expected;
        assert_true (diff > -2 * Duration.SECOND && diff < 2 * Duration.SECOND);
        reset ();
        ((Gtk.ToggleButton) find (win, typeof (Gtk.ToggleButton), "Until")).active = true;
        type ("75");
        press (Gdk.Key.Return);
        assert_true (app.timer.state == TimerState.IDLE);
    });

    Test.add_func ("/finished/view-and-dismiss", () => {
        reset ();
        fake_now = 1000 * Duration.SECOND;
        app.timer.now = () => fake_now;
        type ("1");
        press (Gdk.Key.Return);
        assert_true (app.timer.state == TimerState.RUNNING);
        assert_false (win.has_css_class ("finished"));
        fake_now += Duration.SECOND;
        app.timer.check ();
        assert_true (app.timer.state == TimerState.FINISHED);
        assert_true (win.has_css_class ("finished"));
        assert_true (((Gtk.Button) win.get_focus ()).label == "Dismiss");
        assert_false (win.hide_on_close);
        assert_true (press (Gdk.Key.space));
        assert_true (app.timer.state == TimerState.FINISHED);
        assert_true (press (Gdk.Key.Return));
        assert_true (app.timer.state == TimerState.IDLE);
        assert_false (win.has_css_class ("finished"));
        assert_true (win.get_focus () is WheelColumn);
        app.timer.now = boottime;
    });

    Test.add_func ("/running/space-pauses-and-resumes", () => {
        reset ();
        fake_now = 1000 * Duration.SECOND;
        app.timer.now = () => fake_now;
        type ("10");
        press (Gdk.Key.Return);
        assert_true (win.hide_on_close);
        var line = (Gtk.ProgressBar) find (win, typeof (Gtk.ProgressBar));
        assert_true (line.fraction == 1.0);
        fake_now += 4 * Duration.SECOND;
        app.timer.tick ();
        assert_true (Math.fabs (line.fraction - 0.6) < 1e-9);
        // Pause has focus, so Space goes to the button; with nothing focused the shortcut handles it.
        assert_true (win.get_focus ().tooltip_text == "Pause (Space)");
        assert_false (press (Gdk.Key.space));
        ((Gtk.Button) win.get_focus ()).clicked ();
        assert_true (app.timer.state == TimerState.PAUSED);
        assert_true (win.hide_on_close);
        fake_now += 30 * Duration.SECOND;
        win.set_focus (null);
        assert_true (press (Gdk.Key.space));
        assert_true (app.timer.state == TimerState.RUNNING);
        assert_true (app.timer.remaining == 6 * Duration.SECOND);
        press (Gdk.Key.Escape);
        assert_true (app.timer.state == TimerState.IDLE);
        assert_false (win.hide_on_close);
        app.timer.now = boottime;
    });

    Test.add_func ("/running/until-ignores-space", () => {
        reset ();
        ((Gtk.ToggleButton) find (win, typeof (Gtk.ToggleButton), "Until")).active = true;
        press (Gdk.Key.Return);
        assert_true (app.timer.is_until);
        // Stop has focus in an Until timer; Space must not press it.
        assert_true (win.get_focus ().tooltip_text == "Stop (Esc)");
        assert_true (press (Gdk.Key.space));
        assert_true (app.timer.state == TimerState.RUNNING);
        press (Gdk.Key.Escape);
        assert_true (app.timer.state == TimerState.IDLE);
    });

    Test.add_func ("/alarm/choice-is-stored", () => {
        reset ();
        var dropdown = (Gtk.DropDown) find (win, typeof (Gtk.DropDown));
        var preview = dropdown.get_next_sibling ();
        assert_true (app.settings.get_string ("alarm") == "soft-chime");
        assert_true (dropdown.selected == 0 && preview.sensitive);
        dropdown.selected = 5;
        assert_true (app.settings.get_string ("alarm") == "none");
        assert_false (preview.sensitive);
        dropdown.selected = 1;
        assert_true (app.settings.get_string ("alarm") == "bell");
        assert_true (preview.sensitive);
        dropdown.selected = 0;
    });

    Test.add_func ("/settings/first-run-and-stored", () => {
        reset ();
        // With every key reset the window sees what a first run sees.
        foreach (var key in app.settings.settings_schema.list_keys ()) app.settings.reset (key);
        var first = new TimerWindow (app);
        assert_true (((Gtk.DropDown) find (first, typeof (Gtk.DropDown))).selected == 0);
        assert_true (app.settings.get_double ("alarm-volume") == 0.8);
        assert_true (app.settings.get_string ("presentation-mode") == "window");
        assert_true (app.settings.get_string ("peek-corner") == "top-right");
        first.destroy ();
        first.dispose ();
        app.settings.set_string ("alarm", "pulse");
        var stored = new TimerWindow (app);
        assert_true (((Gtk.DropDown) find (stored, typeof (Gtk.DropDown))).selected == 3);
        stored.destroy ();
        stored.dispose ();
        app.settings.reset ("alarm");
        app.settings.set_double ("alarm-volume", 0.0);
    });

    Test.add_func ("/alarm/play-and-stop", () => {
        reset ();
        app.play_alarm ("none");
        assert_null (app.playing_alarm);
        Test.expect_message (null, LogLevelFlags.LEVEL_WARNING, "*missing*");
        app.play_alarm ("missing");
        Test.assert_expected_messages ();
        assert_null (app.playing_alarm);
        // Every bundled sound starts decoding without a GStreamer error (which would log a fatal warning here).
        // Replacing a sound right away also exercises stopping one that is still preparing.
        foreach (var id in new string[] { "soft-chime", "bell", "digital", "pulse", "classic" }) {
            app.play_alarm (id);
            var loop = new MainLoop ();
            Timeout.add (300, () => {
                loop.quit ();
                return Source.REMOVE;
            });
            loop.run ();
            assert_true (app.playing_alarm == id);
            app.play_alarm (id);
        }
        // Starting a timer silences a preview; so does dismissing a finished one.
        type ("5");
        press (Gdk.Key.Return);
        assert_null (app.playing_alarm);
        app.play_alarm ("bell");
        press (Gdk.Key.Escape);
        assert_null (app.playing_alarm);
    });

    Test.add_func ("/mode/replacement-window", () => {
        reset ();
        type ("1.2.3");
        ((Gtk.Entry) find (win, typeof (Gtk.Entry))).text = "Review PR";
        var next = new TimerWindow (app);
        next.take_setup (win);
        assert_true (((Gtk.Entry) find (next, typeof (Gtk.Entry))).text == "Review PR");
        assert_true (((DurationPicker) find (next, typeof (DurationPicker))).duration == Duration.HOUR + 2 * Duration.MINUTE + 3 * Duration.SECOND);
        // Destroyed windows stop following the timer, so they cannot re-present themselves on finish.
        assert_true (SignalHandler.find (app.timer, SignalMatchType.DATA, 0, 0, null, null, next) != 0);
        next.destroy ();
        next.dispose ();
        assert_true (SignalHandler.find (app.timer, SignalMatchType.DATA, 0, 0, null, null, next) == 0);
        ((Gtk.Entry) find (win, typeof (Gtk.Entry))).text = "";
    });

    Test.add_func ("/peek/states", () => {
        if (!app.can_pin) {
            Test.skip ("no layer shell");
            return;
        }
        reset ();
        fake_now = 1000 * Duration.SECOND;
        app.timer.now = () => fake_now;
        app.label = "Tea";
        app.timer.start (90 * Duration.SECOND);
        var peek = new PeekWindow (app, "bottom-left");
        var labels = new Gtk.Label[0];
        for (var child = peek.child.get_first_child (); child != null; child = child.get_next_sibling ()) {
            if (child is Gtk.Label) labels += (Gtk.Label) child;
        }
        assert_true (labels[0].label == "01:30" && labels[1].label == "Tea");
        assert_true (peek.hide_on_close);
        fake_now += 30 * Duration.SECOND;
        app.timer.pause ();
        assert_true (labels[0].label == "01:00" && labels[1].label == "Paused · Tea");
        assert_true (peek.has_css_class ("paused"));
        app.timer.resume ();
        fake_now += 60 * Duration.SECOND;
        app.timer.check ();
        assert_true (labels[0].label == "Time's up" && peek.has_css_class ("finished"));
        // Closing a finished Peek quits instead of hiding it.
        assert_false (peek.hide_on_close);
        app.timer.stop ();
        app.label = "";
        app.timer.now = boottime;
        peek.destroy ();
        peek.dispose ();
    });

    Test.add_func ("/keys/running-and-modifiers", () => {
        reset ();
        type ("5");
        press (Gdk.Key.Return);
        assert_true (app.timer.state == TimerState.RUNNING);
        assert_false (press (Gdk.Key.@5));
        assert_true (app.timer.state == TimerState.RUNNING);
        app.timer.stop ();
        assert_false (press (Gdk.Key.@5, Gdk.ModifierType.CONTROL_MASK));
        assert_false (press (Gdk.Key.Return, Gdk.ModifierType.ALT_MASK));
        assert_true (app.timer.state == TimerState.IDLE);
    });
}

int main (string[] args) {
    if (!Gtk.init_check ()) {
        print ("1..0 # SKIP no display\n");
        return 0;
    }
    Test.init (ref args);
    app = new Glance.Application ();
    app.flags |= ApplicationFlags.NON_UNIQUE;
    // Connected before any other handler: no presenting and no alarm when a test timer finishes.
    app.timer.finished.connect (() => Signal.stop_emission_by_name (app.timer, "finished"));
    try {
        app.register ();
    } catch (Error e) {
        error ("register: %s", e.message);
    }
    app.settings.set_double ("alarm-volume", 0.0);
    win = new TimerWindow (app);
    var controllers = ((Gtk.Widget) win).observe_controllers ();
    for (uint i = 0; i < controllers.get_n_items (); i++) {
        var c = (Gtk.EventController) controllers.get_item (i);
        if (c.name == "glance-keys") keys = c;
    }
    assert_nonnull (keys);
    add_window_tests ();
    var result = Test.run ();
    win.destroy ();
    return result;
}
