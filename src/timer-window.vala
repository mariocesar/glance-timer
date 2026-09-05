public class Glance.TimerWindow : Gtk.ApplicationWindow {
    public TimerWindow (Gtk.Application app) {
        Object (application: app, title: "Glance", resizable: false);
    }

    construct {
        add_css_class ("glance");
        // Hidden titlebar: no stock header bar, the whole surface drags the window.
        titlebar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { visible = false };

        var brand = new Gtk.Label ("GLANCE") { xalign = 0, css_classes = { "brand" } };
        var countdown = new Gtk.Label ("00:00") { css_classes = { "countdown" } };

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
            margin_top = 14, margin_bottom = 18, margin_start = 18, margin_end = 18,
        };
        box.append (brand);
        box.append (countdown);
        child = new Gtk.WindowHandle () { child = box };
    }
}
