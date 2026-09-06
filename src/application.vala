namespace Glance {
    // Not deprecated in C; only the Vala StyleContext class wrapper is.
    [CCode (cname = "gtk_style_context_add_provider_for_display", cheader_filename = "gtk/gtk.h")]
    extern void add_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    public class Application : Gtk.Application {
        // The one timer; windows only display it.
        public Timer timer { get; default = new Timer (); }
        // Label of the current timer, empty when none was given.
        public string label { get; set; default = ""; }

        public Application () {
            Object (application_id: Config.APP_ID, flags: ApplicationFlags.HANDLES_COMMAND_LINE, version: Config.VERSION);
        }

        public override void startup () {
            base.startup ();
            Gtk.Settings.get_default ().gtk_interface_color_scheme = Gtk.InterfaceColorScheme.DARK;
            var css = new Gtk.CssProvider ();
            css.load_from_resource (resource_base_path + "/style.css");
            add_provider_for_display (Gdk.Display.get_default (), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
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
