public class Glance.TimerWindow : Gtk.ApplicationWindow {
    const string[] ALARMS = { "Soft chime", "Bell", "Digital", "Pulse", "Classic", "Silent", null };
    // GSettings values for ALARMS, in the same order.
    const string[] ALARM_IDS = { "soft-chime", "bell", "digital", "pulse", "classic", "none" };

    unowned Application app;
    DigitEntry entry = new DigitEntry ();

    Gtk.Stack pages;
    Gtk.ToggleButton until_toggle;
    Gtk.Stack setup_modes;
    DurationPicker picker;
    WheelColumn until_hours;
    WheelColumn until_minutes;
    Gtk.Label message;
    Gtk.Entry label_entry;
    Gtk.Box running;
    Gtk.Label status;
    Gtk.Button pause_button;
    Gtk.Button stop_button;
    Gtk.Button dismiss_button;
    Gtk.Image pause_icon;
    Gtk.Label countdown;
    Gtk.Label running_label;
    Gtk.ProgressBar remaining_line;
    Gtk.Label finished_label;
    uint hint_source;
    // Page that last received keyboard focus.
    string focused_page = "";

    // A pinned window is a layer-shell overlay above other windows; the caller checks support.
    public TimerWindow (Application app, bool pinned = false) {
        Object (application: app, title: "Glance", resizable: false);
        this.app = app;

        if (pinned) {
            GtkLayerShell.init_for_window (this);
            GtkLayerShell.set_namespace (this, "glance");
            GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.TOP, true);
            GtkLayerShell.set_anchor (this, GtkLayerShell.Edge.RIGHT, true);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.TOP, 16);
            GtkLayerShell.set_margin (this, GtkLayerShell.Edge.RIGHT, 16);
            GtkLayerShell.set_exclusive_zone (this, 0);
            // niri focuses an on-demand overlay as soon as it appears, so start without keyboard and
            // accept focus (on click) only while the pointer is over Glance or Glance already has it.
            GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
            var pointer = new Gtk.EventControllerMotion ();
            pointer.enter.connect (() => GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.ON_DEMAND));
            pointer.leave.connect (() => {
                if (!is_active) GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
            });
            var focus = new Gtk.EventControllerFocus ();
            focus.leave.connect (() => {
                if (!pointer.contains_pointer) GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);
            });
            ((Gtk.Widget) this).add_controller (pointer);
            ((Gtk.Widget) this).add_controller (focus);
            add_css_class ("pinned");
            // Layer surfaces cannot be moved, so no drag handle.
            child = pages;
        } else {
            // Hidden titlebar: no stock header bar, the whole surface drags the window.
            child = new Gtk.WindowHandle () { child = pages };
        }

        pages.add_named (build_setup (pinned), "setup");
        pages.add_named (build_running (pinned), "running");
        pages.add_named (build_finished (), "finished");
        // Method handlers are dropped automatically when the window is disposed.
        app.timer.notify["state"].connect (sync_page);
        app.timer.tick.connect (refresh_running);
        app.timer.finished.connect (on_finished);
        sync_page ();
    }

    construct {
        add_css_class ("glance");
        titlebar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { visible = false };
        pages = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.CROSSFADE, transition_duration = 150 };

        var keys = new Gtk.EventControllerKey () { propagation_phase = Gtk.PropagationPhase.CAPTURE, name = "glance-keys" };
        keys.key_pressed.connect (on_key);
        ((Gtk.Widget) this).add_controller (keys);
    }

    // A replaced window is disposed (Application.present_mode); its Until hint timeout must stop too.
    public override void dispose () {
        if (hint_source != 0) Source.remove (hint_source);
        hint_source = 0;
        base.dispose ();
    }

    // Carries the setup screen over from the window this one replaces.
    public void take_setup (TimerWindow old) {
        var duration = old.picker.duration;
        picker.set_fields ((int) (duration / Duration.HOUR), (int) (duration / Duration.MINUTE % 60), (int) (duration / Duration.SECOND % 60));
        until_toggle.active = old.until_toggle.active;
        until_hours.select (old.until_hours.value);
        until_minutes.select (old.until_minutes.value);
        if (until_toggle.active) update_hint ();
        label_entry.text = old.label_entry.text;
    }

    void on_finished () {
        announce ("Time's up", Gtk.AccessibleAnnouncementPriority.HIGH);
        // Only surface a hidden window: presenting a visible one steals keyboard focus on niri,
        // and the next keystroke typed elsewhere would dismiss the alert unseen.
        if (!get_visible ()) present ();
    }

    // Pin or unpin, in the window's header. Hidden where layer shell is unavailable.
    Gtk.Button build_pin_button (bool pinned) {
        var button = new Gtk.Button () {
            css_classes = { "icon" },
            valign = Gtk.Align.CENTER,
            tooltip_text = pinned ? "Unpin" : "Keep above other windows",
            visible = app.can_pin,
            child = new Gtk.Image.from_icon_name ("glance-pin-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION },
        };
        if (pinned) button.add_css_class ("active");
        button.update_property (Gtk.AccessibleProperty.LABEL, pinned ? "Unpin window" : "Pin above other windows", -1);
        button.clicked.connect (() => app.present_mode (pinned ? "window" : "pinned"));
        return button;
    }

    Gtk.Widget build_setup (bool pinned) {
        var duration_toggle = new Gtk.ToggleButton.with_label ("Duration") { active = true };
        until_toggle = new Gtk.ToggleButton.with_label ("Until") { group = duration_toggle };
        until_toggle.toggled.connect (on_mode_toggled);
        var modes = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { css_classes = { "mode-switch" }, valign = Gtk.Align.CENTER };
        modes.append (duration_toggle);
        modes.append (until_toggle);
        // Until hint or validation error, next to the mode switch.
        message = new Gtk.Label ("") { xalign = 1, hexpand = true, css_classes = { "message" }, ellipsize = Pango.EllipsizeMode.END };
        var about = new Gtk.Button () {
            css_classes = { "icon" },
            valign = Gtk.Align.CENTER,
            tooltip_text = "About",
            child = new Gtk.Image.from_icon_name ("glance-about-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION },
        };
        about.update_property (Gtk.AccessibleProperty.LABEL, "About Glance", -1);
        about.clicked.connect (show_about);
        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        header.append (modes);
        header.append (message);
        header.append (build_pin_button (pinned));
        header.append (about);

        picker = new DurationPicker ();
        picker.set_fields (0, 25, 0);
        picker.changed.connect (() => {
            entry.clear ();
            set_message ("", false);
        });

        setup_modes = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.CROSSFADE, transition_duration = 120, hhomogeneous = true, vhomogeneous = true };
        setup_modes.add_named (picker, "duration");
        setup_modes.add_named (build_until (), "until");


        var start_button = new Gtk.Button () {
            css_classes = { "start" },
            valign = Gtk.Align.CENTER,
            tooltip_text = "Start (Enter)",
            child = new Gtk.Image.from_icon_name ("glance-start-symbolic") { pixel_size = 22, accessible_role = Gtk.AccessibleRole.PRESENTATION },
        };
        start_button.update_property (Gtk.AccessibleProperty.LABEL, "Start timer", -1);
        start_button.clicked.connect (start);

        setup_modes.hexpand = true;
        var middle = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 32);
        middle.append (setup_modes);
        middle.append (start_button);

        label_entry = new Gtk.Entry () { placeholder_text = "Add label", max_length = 40, hexpand = true };
        label_entry.update_property (Gtk.AccessibleProperty.LABEL, "Timer label", -1);
        var alarm = new Gtk.DropDown.from_strings (ALARMS) { tooltip_text = "Alarm sound" };
        // The button shows a bell before the sound name; the popup list shows names only.
        var with_bell = new Gtk.SignalListItemFactory ();
        with_bell.setup.connect ((object) => {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            row.append (new Gtk.Image.from_icon_name ("glance-alarm-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION });
            row.append (new Gtk.Label (""));
            ((Gtk.ListItem) object).child = row;
        });
        with_bell.bind.connect ((object) => {
            var item = (Gtk.ListItem) object;
            ((Gtk.Label) item.child.get_last_child ()).label = ((Gtk.StringObject) item.item).get_string ();
        });
        var plain = new Gtk.SignalListItemFactory ();
        plain.setup.connect ((object) => ((Gtk.ListItem) object).child = new Gtk.Label ("") { xalign = 0 });
        plain.bind.connect ((object) => {
            var item = (Gtk.ListItem) object;
            ((Gtk.Label) item.child).label = ((Gtk.StringObject) item.item).get_string ();
        });
        alarm.factory = with_bell;
        alarm.list_factory = plain;
        var alarm_caption = new Gtk.Label ("Alarm sound") { visible = false };
        // GtkDropDown names itself after the selection; a labelled-by relation takes precedence.
        alarm.update_relation (Gtk.AccessibleRelation.LABELLED_BY, alarm_caption, null, -1);
        var preview = new Gtk.Button () {
            css_classes = { "icon" },
            valign = Gtk.Align.CENTER,
            tooltip_text = "Preview",
            child = new Gtk.Image.from_icon_name ("glance-preview-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION },
        };
        preview.update_property (Gtk.AccessibleProperty.LABEL, "Preview alarm sound", -1);
        preview.clicked.connect (() => app.play_alarm (ALARM_IDS[alarm.selected]));
        var stored = app.settings.get_string ("alarm");
        for (uint i = 0; i < ALARM_IDS.length; i++) {
            if (ALARM_IDS[i] == stored) alarm.selected = i;
        }
        preview.sensitive = ALARM_IDS[alarm.selected] != "none";
        alarm.notify["selected"].connect (() => {
            app.settings.set_string ("alarm", ALARM_IDS[alarm.selected]);
            preview.sensitive = ALARM_IDS[alarm.selected] != "none";
        });
        var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { css_classes = { "footer" } };
        footer.append (label_entry);
        footer.append (alarm_caption);
        footer.append (alarm);
        footer.append (preview);

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) { css_classes = { "setup" } };
        box.append (header);
        box.append (middle);
        box.append (footer);
        return box;
    }

    Gtk.Widget build_until () {
        var grid = new Gtk.Grid () { css_classes = { "duration-picker" }, halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER, column_spacing = 8 };
        grid.update_property (Gtk.AccessibleProperty.LABEL, "Until time", -1);
        until_hours = new WheelColumn ("Hour", 23);
        until_minutes = new WheelColumn ("Minute", 59);
        grid.attach (until_hours, 0, 0);
        grid.attach (new Gtk.Label (":") { css_classes = { "separator" }, valign = Gtk.Align.CENTER, accessible_role = Gtk.AccessibleRole.PRESENTATION }, 1, 0);
        grid.attach (until_minutes, 2, 0);
        until_hours.changed.connect (on_until_changed);
        until_minutes.changed.connect (on_until_changed);
        return grid;
    }

    Gtk.Widget build_running (bool pinned) {
        // PAUSED indicator on the left, pause and stop on the right.
        status = new Gtk.Label ("Paused") { css_classes = { "status" } };
        pause_icon = new Gtk.Image.from_icon_name ("glance-pause-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION };
        // Clicks leave focus on Pause, so a later Space never presses the button clicked last.
        pause_button = new Gtk.Button () { css_classes = { "icon" }, valign = Gtk.Align.CENTER, child = pause_icon, focus_on_click = false };
        pause_button.clicked.connect (toggle_pause);
        stop_button = new Gtk.Button () {
            css_classes = { "icon" },
            valign = Gtk.Align.CENTER,
            tooltip_text = "Stop (Esc)",
            focus_on_click = false,
            child = new Gtk.Image.from_icon_name ("glance-stop-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION },
        };
        stop_button.update_property (Gtk.AccessibleProperty.LABEL, "Stop timer", -1);
        stop_button.clicked.connect (() => app.timer.stop ());
        var controls = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        controls.append (pause_button);
        controls.append (stop_button);
        controls.append (build_pin_button (pinned));
        var header = new Gtk.CenterBox () { start_widget = status, end_widget = controls };

        countdown = new Gtk.Label ("") { css_classes = { "countdown" }, accessible_role = Gtk.AccessibleRole.TIMER };
        running_label = new Gtk.Label ("") { css_classes = { "running-label" }, ellipsize = Pango.EllipsizeMode.END };
        var center = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { vexpand = true, valign = Gtk.Align.CENTER };
        center.append (countdown);
        center.append (running_label);

        // Repeats the countdown, so screen readers skip it.
        remaining_line = new Gtk.ProgressBar () { css_classes = { "remaining" }, accessible_role = Gtk.AccessibleRole.PRESENTATION };

        running = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { css_classes = { "running" } };
        running.append (header);
        running.append (center);
        running.append (remaining_line);
        return running;
    }

    Gtk.Widget build_finished () {
        var title = new Gtk.Label ("Time's up") { css_classes = { "finished-title" } };
        finished_label = new Gtk.Label ("") { css_classes = { "finished-label" }, ellipsize = Pango.EllipsizeMode.END };
        dismiss_button = new Gtk.Button.with_label ("Dismiss") { css_classes = { "dismiss" }, halign = Gtk.Align.CENTER, tooltip_text = "Dismiss (Enter)" };
        dismiss_button.clicked.connect (() => app.timer.stop ());
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { valign = Gtk.Align.CENTER, css_classes = { "finished" } };
        box.append (title);
        box.append (finished_label);
        box.append (dismiss_button);
        return box;
    }

    void show_about () {
        new Gtk.AboutDialog () {
            application = app,
            transient_for = this,
            modal = true,
            program_name = "Glance",
            version = Config.VERSION,
            comments = "A timer that stays visible without getting in your way.",
            website = "https://github.com/mariocesar/glance-timer",
            license_type = Gtk.License.MIT_X11,
            logo_icon_name = Config.APP_ID,
        }.present ();
    }

    bool on_key (uint keyval, uint keycode, Gdk.ModifierType state) {
        if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK)) != 0) return false;
        if (app.timer.state != TimerState.IDLE) {
            switch (keyval) {
            case Gdk.Key.Return: case Gdk.Key.KP_Enter: case Gdk.Key.Escape:
                app.timer.stop ();
                return true;
            case Gdk.Key.space:
                // A focused button takes Space (Pin, reached with Tab), but Space never stops or dismisses.
                var focus = get_focus ();
                if (focus is Gtk.Button && focus != stop_button && app.timer.state != TimerState.FINISHED) return false;
                toggle_pause ();
                return true;
            default:
                return false;
            }
        }
        switch (keyval) {
        case Gdk.Key.Return: case Gdk.Key.KP_Enter:
            start ();
            return true;
        case Gdk.Key.Escape:
            clear ();
            return true;
        }
        // Text fields keep their own digits and Backspace.
        if (get_focus () is Gtk.Editable) return false;
        if (keyval == Gdk.Key.BackSpace) {
            if (entry.backspace ()) show_entry ();
            return true;
        }
        var c = Gdk.keyval_to_unicode (keyval);
        if (c == ',') c = '.';
        if ((c >= '0' && c <= '9') || c == '.') {
            if (entry.push (c)) show_entry ();
            return true;
        }
        return false;
    }

    // Mirrors typed digits on the wheels. In Until mode they read as HHMM.
    void show_entry () {
        int h, m, s;
        entry.fields (out h, out m, out s);
        if (until_toggle.active) {
            if (h > 0) {
                entry.backspace ();
                return;
            }
            until_hours.select (m);
            until_minutes.select (s);
            update_hint ();
        } else {
            picker.set_fields (h, m, s);
            set_message ("", false);
        }
    }

    void start () {
        var label = label_entry.text.strip ();
        if (until_toggle.active) {
            var h = until_hours.value;
            var m = until_minutes.value;
            if (h > 23 || m > 59) {
                set_message ("Enter a time between 00:00 and 23:59", true);
                return;
            }
            var target = Deadline.resolve ("%d:%02d".printf (h, m), new DateTime.now_local ());
            app.label = label;
            app.timer.start_until (target.to_unix () * Duration.SECOND);
        } else {
            var duration = picker.duration;
            if (duration == 0) {
                set_message ("Set a duration first", true);
                return;
            }
            if (duration > Duration.MAX) {
                set_message ("The longest timer is 23:59:59", true);
                return;
            }
            app.label = label;
            app.timer.start (duration);
        }
        entry.clear ();
    }

    void clear () {
        entry.clear ();
        if (until_toggle.active) {
            select_next_quarter_hour ();
        } else {
            picker.set_fields (0, 0, 0);
            set_message ("", false);
        }
    }

    void on_mode_toggled () {
        entry.clear ();
        var until = until_toggle.active;
        setup_modes.visible_child_name = until ? "until" : "duration";
        if (until) {
            select_next_quarter_hour ();
            hint_source = Timeout.add_seconds (15, () => {
                update_hint ();
                return Source.CONTINUE;
            });
        } else {
            if (hint_source != 0) Source.remove (hint_source);
            hint_source = 0;
            set_message ("", false);
        }
    }

    void on_until_changed () {
        entry.clear ();
        update_hint ();
    }

    // Default Until target: at least 15 minutes ahead, on a quarter hour.
    void select_next_quarter_hour () {
        var now = new DateTime.now_local ();
        var minutes = ((now.get_hour () * 60 + now.get_minute () + 15 + 14) / 15 * 15) % (24 * 60);
        until_hours.select (minutes / 60);
        until_minutes.select (minutes % 60);
        update_hint ();
    }

    // "in 1 h 05 min", prefixed with "Tomorrow, " when the target is tomorrow.
    void update_hint () {
        var h = until_hours.value;
        var m = until_minutes.value;
        if (h > 23 || m > 59) {
            set_message ("", false);
            return;
        }
        var now = new DateTime.now_local ();
        var target = Deadline.resolve ("%d:%02d".printf (h, m), now);
        var minutes = (target.difference (now) + Duration.MINUTE - 1) / Duration.MINUTE;
        var text = minutes >= 60 ? "in %lld h %02lld min".printf (minutes / 60, minutes % 60) : "in %lld min".printf (minutes);
        if (Deadline.describe (target, now).has_suffix ("tomorrow")) text = "Tomorrow, " + text;
        set_message (text, false);
    }

    void set_message (string text, bool error) {
        message.label = text;
        if (error) announce (text, Gtk.AccessibleAnnouncementPriority.MEDIUM);
        if (error) message.add_css_class ("error");
        else message.remove_css_class ("error");
    }

    void sync_page () {
        var state = app.timer.state;
        var finished = state == TimerState.FINISHED;
        var page = state == TimerState.IDLE ? "setup" : finished ? "finished" : "running";
        pages.visible_child_name = page;
        // Focus follows the page, so Tab and screen readers never start from a hidden control.
        if (page != focused_page) {
            focused_page = page;
            if (page == "setup") (until_toggle.active ? until_hours : picker.hours).grab_focus ();
            else if (finished) dismiss_button.grab_focus ();
            else (app.timer.is_until ? stop_button : pause_button).grab_focus ();
        }
        // The whole surface changes color so completion is hard to miss.
        if (finished) {
            add_css_class ("finished");
            finished_label.label = app.label;
            finished_label.visible = app.label != "";
        } else {
            remove_css_class ("finished");
        }
        var active = state == TimerState.RUNNING || state == TimerState.PAUSED;
        // Closing the window while a timer counts keeps the process and the timer alive.
        hide_on_close = active;
        if (!active) return;
        var paused = state == TimerState.PAUSED;
        if (paused) {
            running.add_css_class ("paused");
            announce ("Paused", Gtk.AccessibleAnnouncementPriority.MEDIUM);
        } else {
            running.remove_css_class ("paused");
        }
        status.visible = paused;
        pause_icon.icon_name = paused ? "glance-start-symbolic" : "glance-pause-symbolic";
        pause_button.tooltip_text = paused ? "Resume (Space)" : "Pause (Space)";
        pause_button.update_property (Gtk.AccessibleProperty.LABEL, paused ? "Resume timer" : "Pause timer", -1);
        // Until timers cannot be paused.
        pause_button.visible = !app.timer.is_until;
        refresh_running ();
    }

    void toggle_pause () {
        if (app.timer.state == TimerState.RUNNING) app.timer.pause ();
        else app.timer.resume ();
    }

    void refresh_running () {
        if (app.timer.state == TimerState.IDLE) return;
        countdown.label = Duration.format (app.timer.remaining);
        if (countdown.label.length > 5) countdown.add_css_class ("hours");
        else countdown.remove_css_class ("hours");
        remaining_line.fraction = 1.0 - app.timer.progress;
        running_label.label = app.label;
        running_label.visible = app.label != "";
    }
}
