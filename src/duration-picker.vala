// One wheel of the duration picker. Larger values sit above the selected one, so scrolling up,
// the Up key and clicking the upper row all increase the value.
public class Glance.WheelColumn : Gtk.Widget, Gtk.AccessibleRange {
    const int64 ANIMATION_US = 140000;

    public string caption { get; construct; }
    public int max { get; construct; }
    // May exceed max while it shows typed digits; user input brings it back in range.
    public int value { get; private set; }

    // Emitted for user input only, never for select.
    public signal void changed ();

    // Rows of travel still to animate; 0 when the selected value is centred.
    double offset;
    double animation_from;
    int64 animation_start;
    uint animation_id;
    double wheel_delta;
    double surface_delta;

    static construct {
        set_css_name ("wheel");
        set_accessible_role (Gtk.AccessibleRole.SPIN_BUTTON);
    }

    public WheelColumn (string caption, int max) {
        Object (caption: caption, max: max);
    }

    construct {
        focusable = true;
        cursor = new Gdk.Cursor.from_name ("ns-resize", null);

        var scroll = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
        scroll.scroll.connect ((dx, dy) => {
            scroll_by (dy, scroll.get_unit ());
            return true;
        });
        scroll.scroll_end.connect (() => {
            surface_delta = 0;
            animate ();
        });
        add_controller (scroll);

        var keys = new Gtk.EventControllerKey ();
        keys.key_pressed.connect (on_key);
        add_controller (keys);

        var click = new Gtk.GestureClick ();
        click.pressed.connect ((n, x, y) => {
            grab_focus ();
            var third = get_height () / 3.0;
            if (y < third) user_step (1);
            else if (y > 2 * third) user_step (-1);
        });
        add_controller (click);

        update_accessible ();
    }

    public void select (int v) {
        stop_animation ();
        wheel_delta = surface_delta = offset = 0;
        value = v.clamp (0, 99);
        update_accessible ();
        queue_draw ();
    }

    // Scroll input. Wheel notches (fractional on high-resolution wheels) add up to one step each;
    // touchpad travel follows the finger one row per step. A direction change drops leftovers.
    public void scroll_by (double dy, Gdk.ScrollUnit unit) {
        if (dy == 0) return;
        if (unit == Gdk.ScrollUnit.WHEEL) {
            if ((dy > 0) != (wheel_delta > 0)) wheel_delta = 0;
            wheel_delta += dy;
            while (wheel_delta >= 1 || wheel_delta <= -1) {
                var d = wheel_delta > 0 ? 1 : -1;
                wheel_delta -= d;
                user_step (-d);
            }
            return;
        }
        var pitch = row_pitch ();
        surface_delta += dy;
        while (surface_delta >= pitch || surface_delta <= -pitch) {
            var d = surface_delta > 0 ? 1 : -1;
            surface_delta -= d * pitch;
            move (-d);
            changed ();
        }
        stop_animation ();
        offset = surface_delta / pitch;
        queue_draw ();
    }

    // Steps by `d` with wrap-around, animated.
    public void user_step (int d) {
        move (d);
        offset = (offset + d).clamp (-2, 2);
        animate ();
        changed ();
    }

    // Lets assistive technology set the value directly.
    bool set_current_value (double v) {
        var d = ((int) v).clamp (0, max) - int.min (value, max);
        if (d != 0) user_step (d);
        return true;
    }

    void move (int d) {
        var n = max + 1;
        var from = int.min (value, max);
        value = ((from + d) % n + n) % n;
        update_accessible ();
    }

    bool on_key (uint keyval, uint keycode, Gdk.ModifierType state) {
        if ((state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK)) != 0) return false;
        switch (keyval) {
        case Gdk.Key.Up: case Gdk.Key.KP_Up: user_step (1); return true;
        case Gdk.Key.Down: case Gdk.Key.KP_Down: user_step (-1); return true;
        case Gdk.Key.Page_Up: case Gdk.Key.KP_Page_Up: user_step (5); return true;
        case Gdk.Key.Page_Down: case Gdk.Key.KP_Page_Down: user_step (-5); return true;
        case Gdk.Key.Home: case Gdk.Key.KP_Home: user_step (-int.min (value, max)); return true;
        case Gdk.Key.End: case Gdk.Key.KP_End: user_step (max - int.min (value, max)); return true;
        default: return false;
        }
    }

    void animate () {
        if (offset == 0) return;
        if (!Gtk.Settings.get_default ().gtk_enable_animations) {
            offset = 0;
            queue_draw ();
            return;
        }
        animation_from = offset;
        animation_start = -1;
        if (animation_id == 0) animation_id = add_tick_callback (on_frame);
    }

    bool on_frame (Gtk.Widget widget, Gdk.FrameClock clock) {
        var now = clock.get_frame_time ();
        if (animation_start < 0) animation_start = now;
        var t = (double) (now - animation_start) / ANIMATION_US;
        if (t >= 1) {
            offset = 0;
            animation_id = 0;
            queue_draw ();
            return Source.REMOVE;
        }
        var u = 1 - t;
        offset = animation_from * u * u * u;
        queue_draw ();
        return Source.CONTINUE;
    }

    void stop_animation () {
        if (animation_id != 0) {
            remove_tick_callback (animation_id);
            animation_id = 0;
        }
    }

    void update_accessible () {
        update_property (
            Gtk.AccessibleProperty.LABEL, caption,
            Gtk.AccessibleProperty.VALUE_MIN, 0.0,
            Gtk.AccessibleProperty.VALUE_MAX, (double) max,
            Gtk.AccessibleProperty.VALUE_NOW, (double) value,
            Gtk.AccessibleProperty.VALUE_TEXT, "%d %s".printf (value, caption.down ()),
            -1);
    }

    // Vertical distance between rows, from the current font.
    double row_pitch () {
        int w, h;
        create_pango_layout ("00").get_pixel_size (out w, out h);
        return h * 0.82;
    }

    public override Gtk.SizeRequestMode get_request_mode () {
        return Gtk.SizeRequestMode.CONSTANT_SIZE;
    }

    public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        int w, h;
        create_pango_layout ("00").get_pixel_size (out w, out h);
        minimum = natural = orientation == Gtk.Orientation.HORIZONTAL ? (int) (w * 1.5) : (int) (h * 0.82 * 3);
        minimum_baseline = natural_baseline = -1;
    }

    public override void snapshot (Gtk.Snapshot snapshot) {
        var width = get_width ();
        var height = get_height ();
        var mid = height / 2.0f;
        var pitch = (float) row_pitch ();
        var color = get_color ();
        var layout = create_pango_layout (null);

        // Hairlines framing the selected row.
        var line = color;
        line.alpha *= 0.12f;
        snapshot.append_color (line, { { width * 0.15f, mid - pitch / 2 }, { width * 0.7f, 1 } });
        snapshot.append_color (line, { { width * 0.15f, mid + pitch / 2 }, { width * 0.7f, 1 } });

        snapshot.push_clip ({ { 0, 0 }, { width, height } });
        for (int k = -2; k <= 2; k++) {
            if (value > max && k != 0) continue;
            var position = k + offset;
            var distance = position < 0 ? -position : position;
            if (distance >= 1.8) continue;
            var near = double.min (distance, 1.0);
            var scale = (float) (1.0 - 0.45 * near);
            var alpha = (float) ((1.0 - 0.7 * near) * double.min ((1.8 - distance) / 0.8, 1.0));

            var n = max + 1;
            layout.set_text ("%02d".printf (value > max ? value : ((value + k) % n + n) % n), -1);
            int tw, th;
            layout.get_pixel_size (out tw, out th);
            var tint = color;
            tint.alpha *= alpha;

            snapshot.save ();
            snapshot.translate ({ width / 2.0f, mid - (float) position * pitch });
            snapshot.scale (scale, scale);
            snapshot.translate ({ -tw / 2.0f, -th / 2.0f });
            snapshot.append_layout (layout, tint);
            snapshot.restore ();
        }
        snapshot.pop ();
    }
}

// Hours, minutes and seconds wheels separated by colons.
public class Glance.DurationPicker : Gtk.Grid {
    public WheelColumn hours { get; private set; }
    public WheelColumn minutes { get; private set; }
    public WheelColumn seconds { get; private set; }

    // Emitted when the user changes any wheel.
    public signal void changed ();

    public int64 duration {
        get { return hours.value * Duration.HOUR + minutes.value * Duration.MINUTE + seconds.value * Duration.SECOND; }
    }

    static construct {
        set_accessible_role (Gtk.AccessibleRole.GROUP);
    }

    construct {
        add_css_class ("duration-picker");
        column_spacing = 8;
        update_property (Gtk.AccessibleProperty.LABEL, "Duration", -1);
        hours = add_wheel ("Hours", 23, 0);
        attach (new Gtk.Label (":") { css_classes = { "separator" }, valign = Gtk.Align.CENTER, accessible_role = Gtk.AccessibleRole.PRESENTATION }, 1, 0);
        minutes = add_wheel ("Minutes", 59, 2);
        attach (new Gtk.Label (":") { css_classes = { "separator" }, valign = Gtk.Align.CENTER, accessible_role = Gtk.AccessibleRole.PRESENTATION }, 3, 0);
        seconds = add_wheel ("Seconds", 59, 4);
    }

    public void set_fields (int h, int m, int s) {
        hours.select (h);
        minutes.select (m);
        seconds.select (s);
    }

    WheelColumn add_wheel (string caption, int max, int column) {
        var wheel = new WheelColumn (caption, max);
        wheel.changed.connect (() => changed ());
        attach (wheel, column, 0);
        return wheel;
    }
}
