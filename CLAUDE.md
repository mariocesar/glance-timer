# Glance

Compact keyboard-first desktop timer for Linux/Wayland (niri primary). Vala + GTK4 + Meson.

## Commands

    meson setup build
    meson compile -C build
    meson test -C build
    meson devenv -C build glance   # uninstalled run with schema from the build dir

## Rules

- Stack is fixed: Vala, GTK4, GLib/GIO, Meson.
- Timer uses absolute deadlines on a suspend-aware monotonic clock (CLOCK_BOOTTIME), never a decrementing counter. The timer, not the window, owns the tick.
- One timer, no telemetry, no network, no database.
- Custom widgets must stay accessible (names, keyboard operation).
- Layer Shell only when `GtkLayerShell.is_supported()`; degrade gracefully otherwise.
- Never modify the user's niri config or install system packages without approval.
