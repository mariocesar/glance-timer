public class Glance.TimerWindow : Gtk.ApplicationWindow {
    const string[] ALARMS = { "Soft chime", "Bell", "Digital", "Pulse", "Classic", "Silent", null };

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
    Gtk.Label countdown;
    Gtk.Label running_label;
    Gtk.Label finished_label;
    uint hint_source;

    public TimerWindow (Application app) {
        Object (application: app, title: "Glance", resizable: false);
        this.app = app;

        pages.add_named (build_setup (), "setup");
        pages.add_named (build_running (), "running");
        pages.add_named (build_finished (), "finished");
        app.timer.notify["state"].connect (sync_page);
        app.timer.tick.connect (refresh_running);
        app.timer.finished.connect (() => {
            announce ("Time's up", Gtk.AccessibleAnnouncementPriority.HIGH);
            // Only surface a hidden window: presenting a visible one steals keyboard focus on niri,
            // and the next keystroke typed elsewhere would dismiss the alert unseen.
            if (!get_visible ()) present ();
        });
        sync_page ();
    }

    construct {
        add_css_class ("glance");
        // Hidden titlebar: no stock header bar, the whole surface drags the window.
        titlebar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { visible = false };
        pages = new Gtk.Stack () { transition_type = Gtk.StackTransitionType.CROSSFADE, transition_duration = 150 };
        child = new Gtk.WindowHandle () { child = pages };

        var keys = new Gtk.EventControllerKey () { propagation_phase = Gtk.PropagationPhase.CAPTURE, name = "glance-keys" };
        keys.key_pressed.connect (on_key);
        ((Gtk.Widget) this).add_controller (keys);
    }

    Gtk.Widget build_setup () {
        var duration_toggle = new Gtk.ToggleButton.with_label ("Duration") { active = true };
        until_toggle = new Gtk.ToggleButton.with_label ("Until") { group = duration_toggle };
        until_toggle.toggled.connect (on_mode_toggled);
        var modes = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { css_classes = { "mode-switch" }, valign = Gtk.Align.CENTER };
        modes.append (duration_toggle);
        modes.append (until_toggle);
        // Until hint or validation error, next to the mode switch.
        message = new Gtk.Label ("") { xalign = 1, hexpand = true, css_classes = { "message" }, ellipsize = Pango.EllipsizeMode.END };
        var about = new Gtk.Button () {
            css_classes = { "about" },
            valign = Gtk.Align.CENTER,
            tooltip_text = "About",
            child = new Gtk.Image.from_icon_name ("glance-about-symbolic") { accessible_role = Gtk.AccessibleRole.PRESENTATION },
        };
        about.update_property (Gtk.AccessibleProperty.LABEL, "About Glance", -1);
        about.clicked.connect (show_about);
        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        header.append (modes);
        header.append (message);
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
        var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { css_classes = { "footer" } };
        footer.append (label_entry);
        footer.append (alarm_caption);
        footer.append (alarm);

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
        grid.attach (new Gtk.Label (":") { css_classes = { "separator" }, valign = Gtk.Align.CENTER }, 1, 0);
        grid.attach (until_minutes, 2, 0);
        until_hours.changed.connect (on_until_changed);
        until_minutes.changed.connect (on_until_changed);
        return grid;
    }

    Gtk.Widget build_running () {
        countdown = new Gtk.Label ("") { css_classes = { "countdown" } };
        running_label = new Gtk.Label ("") { css_classes = { "running-label" }, ellipsize = Pango.EllipsizeMode.END };
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) { valign = Gtk.Align.CENTER, css_classes = { "running" } };
        box.append (countdown);
        box.append (running_label);
        return box;
    }

    Gtk.Widget build_finished () {
        var title = new Gtk.Label ("Time's up") { css_classes = { "finished-title" } };
        finished_label = new Gtk.Label ("") { css_classes = { "finished-label" }, ellipsize = Pango.EllipsizeMode.END };
        var dismiss = new Gtk.Button.with_label ("Dismiss") { css_classes = { "dismiss" }, halign = Gtk.Align.CENTER, tooltip_text = "Dismiss (Enter)" };
        dismiss.clicked.connect (() => app.timer.stop ());
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) { valign = Gtk.Align.CENTER, css_classes = { "finished" } };
        box.append (title);
        box.append (finished_label);
        box.append (dismiss);
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
            website = "https://github.com/mariocesar/glance",
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
        if (error) message.add_css_class ("error");
        else message.remove_css_class ("error");
    }

    void sync_page () {
        var state = app.timer.state;
        var finished = state == TimerState.FINISHED;
        pages.visible_child_name = state == TimerState.IDLE ? "setup" : finished ? "finished" : "running";
        // The whole surface changes color so completion is hard to miss.
        if (finished) {
            add_css_class ("finished");
            finished_label.label = app.label;
            finished_label.visible = app.label != "";
        } else {
            remove_css_class ("finished");
        }
        if (state == TimerState.RUNNING || state == TimerState.PAUSED) refresh_running ();
    }

    void refresh_running () {
        if (app.timer.state == TimerState.IDLE) return;
        countdown.label = Duration.format (app.timer.remaining);
        running_label.label = app.label;
        running_label.visible = app.label != "";
    }
}
