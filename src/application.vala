namespace Glance {
    // Not deprecated in C; only the Vala StyleContext class wrapper is.
    [CCode (cname = "gtk_style_context_add_provider_for_display", cheader_filename = "gtk/gtk.h")]
    extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    public class Application : Gtk.Application {
        // Options that each ask for one thing; a positional duration counts as one more.
        const string[] ACTIONS = { "until", "pause", "resume", "stop", "reset", "add", "show", "hide" };

        // The one timer; windows only display it.
        public Timer timer { get; default = new Timer (); }
        // Label of the current timer, empty when none was given.
        public string label { get; set; default = ""; }
        public GLib.Settings settings { get; private set; }
        // Id of the sound playing now, null when silent.
        public string? playing_alarm { get; private set; }
        Gst.Element? player;

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_COMMAND_LINE, version: Config.VERSION);
            add_main_option ("until", 'u', 0, OptionArg.STRING, "Count down to a time of day", "HH:MM");
            add_main_option ("label", 'l', 0, OptionArg.STRING, "Label for the new timer", "TEXT");
            add_main_option ("pause", 0, 0, OptionArg.NONE, "Pause the timer", null);
            add_main_option ("resume", 0, 0, OptionArg.NONE, "Resume a paused timer", null);
            add_main_option ("stop", 0, 0, OptionArg.NONE, "Stop the timer, or dismiss a finished one", null);
            add_main_option ("reset", 0, 0, OptionArg.NONE, "Restart the timer from its full duration", null);
            add_main_option ("add", 'a', 0, OptionArg.STRING, "Add time to the timer", "DURATION");
            add_main_option ("show", 0, 0, OptionArg.NONE, "Show the window", null);
            add_main_option ("hide", 0, 0, OptionArg.NONE, "Hide the window, like closing it", null);
            add_main_option (OPTION_REMAINING, 0, 0, OptionArg.STRING_ARRAY, "", "[DURATION]");
            set_option_context_summary ("""Start a timer, or control the one already running.

  glance 25m                          start a 25 minute timer
  glance 1h 30m --label "Deep work"   durations use h, m and s
  glance --until 14:30                count down to 14:30
  glance --add 5m                     add five minutes""");
        }

        // Rejects malformed commands in the calling process, before anything reaches the running instance.
        public override int handle_local_options (VariantDict options) {
            var actions = 0;
            foreach (var name in ACTIONS) {
                if (options.contains (name)) actions++;
            }
            var rest = options.lookup_value (OPTION_REMAINING, VariantType.STRING_ARRAY);
            if (rest != null) actions++;
            string? error = null;
            string? text = null;
            if (actions > 1) {
                error = "use one action at a time";
            } else if (options.contains ("label") && rest == null && !options.contains ("until")) {
                error = "--label needs a duration or --until";
            } else if (options.lookup ("until", "s", out text) && Deadline.resolve (text, new DateTime.now_local ()) == null) {
                error = "can't read the time \"%s\"; use HH:MM, for example 14:30".printf (text);
            } else if (rest != null || options.lookup ("add", "s", out text)) {
                if (rest != null) text = string.joinv (" ", rest.get_strv ());
                var duration = Duration.parse (text);
                if (Regex.match_simple ("^[0-9]+$", text.strip ())) {
                    error = "add a unit to \"%s\", for example %sm or %ss".printf (text.strip (), text.strip (), text.strip ());
                } else if (duration < 0) {
                    error = "can't read the duration \"%s\"; try 25m, 1h30m or 45s".printf (text);
                } else if (duration == 0) {
                    error = "the duration must be more than zero";
                } else if (duration > Duration.MAX && rest != null) {
                    error = "the longest timer is 23:59:59";
                }
            }
            if (error == null) return -1;
            printerr ("glance: %s\n", error);
            return 1;
        }

        public override void startup () {
            base.startup ();
            Gtk.Settings.get_default ().gtk_interface_color_scheme = Gtk.InterfaceColorScheme.DARK;
            var css = new Gtk.CssProvider ();
            css.load_from_resource (resource_base_path + "/style.css");
            add_provider_for_display (Gdk.Display.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            unowned string[]? no_args = null;
            Gst.init (ref no_args);
            settings = new GLib.Settings (Config.APP_ID);
            timer.finished.connect (() => play_alarm (settings.get_string ("alarm")));
            // Dismissing, stopping or starting silences the alarm or a preview.
            timer.notify["state"].connect (() => {
                if (timer.state != TimerState.FINISHED) stop_alarm ();
            });
        }

        // Plays a bundled sound once. Failures are only logged: the finished view never depends on audio.
        public void play_alarm (string id) {
            stop_alarm ();
            if (id == "none") return;
            var path = "%s/sounds/%s.ogg".printf (resource_base_path, id);
            try {
                resources_get_info (path, ResourceLookupFlags.NONE, null, null);
            } catch (Error e) {
                warning ("Alarm sound %s: %s", id, e.message);
                return;
            }
            // playbin rather than Gtk.MediaFile, which crashes when stopped while still preparing.
            if (player == null) {
                player = Gst.ElementFactory.make ("playbin", "alarm");
                if (player == null) {
                    warning ("Alarm sound: GStreamer playbin is not available");
                    return;
                }
                player.get_bus ().add_watch (Priority.DEFAULT, (bus, message) => {
                    if (message.type == Gst.MessageType.ERROR) {
                        Error error;
                        string debug;
                        message.parse_error (out error, out debug);
                        warning ("Alarm sound %s: %s", playing_alarm, error.message);
                        stop_alarm ();
                    } else if (message.type == Gst.MessageType.EOS) {
                        stop_alarm ();
                    }
                    return Source.CONTINUE;
                });
            }
            player.set ("uri", "resource://" + path, "volume", settings.get_double ("alarm-volume"));
            player.set_state (Gst.State.PLAYING);
            playing_alarm = id;
        }

        public void stop_alarm () {
            if (player != null) player.set_state (Gst.State.NULL);
            playing_alarm = null;
        }

        public override void activate () {
            var window = active_window ?? new TimerWindow (this);
            window.present ();
        }

        // Runs in the primary instance for every invocation, local or forwarded. Input was validated locally.
        public override int command_line (ApplicationCommandLine command_line) {
            var options = command_line.get_options_dict ();
            var rest = options.lookup_value (OPTION_REMAINING, VariantType.STRING_ARRAY);
            string? until = null;
            string? add = null;
            string? new_label = null;
            options.lookup ("until", "s", out until);
            options.lookup ("add", "s", out add);
            options.lookup ("label", "s", out new_label);
            var state = timer.state;
            var not_running = state == TimerState.FINISHED ? "the timer has already finished" : "no timer is running";
            string? error = null;

            if (rest != null || until != null) {
                label = new_label ?? "";
                if (rest != null) {
                    timer.start (Duration.parse (string.joinv (" ", rest.get_strv ())));
                } else {
                    timer.start_until (Deadline.resolve (until, new DateTime.now_local ()).to_unix () * Duration.SECOND);
                }
                // Show a hidden or new window, but don't take focus from a visible one.
                var window = active_window ?? new TimerWindow (this);
                if (!window.visible) window.present ();
            } else if (options.contains ("pause")) {
                if (state == TimerState.RUNNING && timer.is_until) error = "Until timers can't be paused; use --stop";
                else if (state == TimerState.PAUSED) error = "the timer is already paused";
                else if (!timer.pause ()) error = not_running;
            } else if (options.contains ("resume")) {
                if (state == TimerState.RUNNING) error = "the timer is not paused";
                else if (!timer.resume ()) error = not_running;
            } else if (options.contains ("stop")) {
                if (state == TimerState.IDLE) {
                    error = not_running;
                } else {
                    timer.stop ();
                    // Nothing left to show: a hidden window closes, which quits.
                    if (active_window != null && !active_window.visible) active_window.close ();
                }
            } else if (options.contains ("reset")) {
                if (state == TimerState.IDLE) {
                    error = not_running;
                } else if (timer.is_until) {
                    error = "Until timers can't be restarted";
                } else {
                    timer.start (timer.total);
                    if (state == TimerState.PAUSED) timer.pause ();
                }
            } else if (add != null) {
                if (!timer.add (Duration.parse (add))) error = not_running;
            } else if (options.contains ("hide")) {
                if (active_window != null) active_window.close ();
            } else {
                activate ();
            }

            if (error == null) return 0;
            command_line.printerr ("glance: %s\n", error);
            return 1;
        }
    }
}
