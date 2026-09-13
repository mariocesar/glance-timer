namespace Glance {
    // Not deprecated in C; only the Vala StyleContext class wrapper is.
    [CCode (cname = "gtk_style_context_add_provider_for_display", cheader_filename = "gtk/gtk.h")]
    extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    public class Application : Gtk.Application {
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

        public override int command_line (ApplicationCommandLine command_line) {
            activate ();
            return 0;
        }
    }
}
