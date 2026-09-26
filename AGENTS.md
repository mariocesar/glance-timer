# Glance

Keyboard-first countdown timer for Linux/Wayland, niri first. Vala, GTK 4, Meson.

## Layout

    src/              application, timer, duration and deadline parsing, picker, windows
    data/             desktop, metainfo, gschema and gresource templates; CSS, icons, sounds
    tests/            unit, widget and CLI tests
    packaging/arch/   PKGBUILD
    screenshots/      README images, retaken with `just screenshots`

## Verify

    meson setup build
    meson compile -C build
    meson test -C build
    meson devenv -C build glance-timer

## Conventions

- Vala, GTK 4, GLib/GIO and Meson only.
- The timer owns the tick: absolute deadlines on CLOCK_BOOTTIME, never a counter that counts down.
- Custom widgets keep accessible names and full keyboard control.
- Layer shell only when `GtkLayerShell.is_supported()`; a plain window otherwise.
- Commit subjects are plain imperative sentences. Comments and docs stay short.

## Non-goals

- More than one timer, history, accounts, sync.
- Network, telemetry, a database.
- Editing the user's niri config.
