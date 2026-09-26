// Peek: a compact corner overlay with the remaining time, the label and a thin progress line.
// It never takes keyboard focus; a click brings back the full window.
public class Glance.PeekWindow : Gtk.ApplicationWindow {
    unowned Application app;
    Gtk.Label countdown;
    Gtk.Label caption;
    Gtk.ProgressBar remaining_line;

    public PeekWindow (Application app, string corner) {
        Object (application: app, title: "Glance", resizable: false, hide_on_close: true);
        this.app = app;
        add_css_class ("glance");
        add_css_class ("peek");
        titlebar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) { visible = false };
        tooltip_text = "Open Glance";

        GtkLayerShell.init_for_window (this);
        GtkLayerShell.set_namespace (this, "glance");
        GtkLayerShell.set_layer (this, GtkLayerShell.Layer.OVERLAY);
        var vertical = corner.has_prefix ("bottom") ? GtkLayerShell.Edge.BOTTOM : GtkLayerShell.Edge.TOP;
        var horizontal = corner.has_suffix ("left") ? GtkLayerShell.Edge.LEFT : GtkLayerShell.Edge.RIGHT;
        GtkLayerShell.set_anchor (this, vertical, true);
        GtkLayerShell.set_anchor (this, horizontal, true);
        GtkLayerShell.set_margin (this, vertical, 16);
        GtkLayerShell.set_margin (this, horizontal, 16);
        GtkLayerShell.set_exclusive_zone (this, 0);
        GtkLayerShell.set_keyboard_mode (this, GtkLayerShell.KeyboardMode.NONE);

        countdown = new Gtk.Label ("") { css_classes = { "peek-countdown" }, accessible_role = Gtk.AccessibleRole.TIMER };
        caption = new Gtk.Label ("") { css_classes = { "peek-caption" }, ellipsize = Pango.EllipsizeMode.END, max_width_chars = 18 };
        remaining_line = new Gtk.ProgressBar () { css_classes = { "remaining" }, accessible_role = Gtk.AccessibleRole.PRESENTATION };
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { css_classes = { "peek-body" } };
        box.append (countdown);
        box.append (caption);
        box.append (remaining_line);
        child = box;

        var click = new Gtk.GestureClick ();
        click.released.connect (() => app.present_mode ("window"));
        ((Gtk.Widget) this).add_controller (click);

        // Method handlers are dropped automatically when the window is disposed.
        app.timer.notify["state"].connect (refresh);
        app.timer.tick.connect (refresh);
        app.timer.finished.connect (on_finished);
        refresh ();
    }

    void on_finished () {
        announce ("Time's up", Gtk.AccessibleAnnouncementPriority.HIGH);
        if (!get_visible ()) present ();
    }

    void refresh () {
        var state = app.timer.state;
        if (state == TimerState.IDLE) return;
        var finished = state == TimerState.FINISHED;
        var paused = state == TimerState.PAUSED;
        // Like the full window: closing hides a counting timer, but closing a finished one quits.
        hide_on_close = !finished;
        if (finished) add_css_class ("finished");
        else remove_css_class ("finished");
        if (paused) add_css_class ("paused");
        else remove_css_class ("paused");

        countdown.label = finished ? "Time's up" : Duration.format (app.timer.remaining);
        if (countdown.label.length > 5 && !finished) countdown.add_css_class ("hours");
        else countdown.remove_css_class ("hours");
        var text = app.label;
        if (paused) text = text == "" ? "Paused" : "Paused · " + text;
        caption.label = text;
        caption.visible = text != "";
        remaining_line.visible = !finished;
        remaining_line.fraction = 1.0 - app.timer.progress;
    }
}
