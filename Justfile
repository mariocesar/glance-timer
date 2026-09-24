run:
    -pkill -x glance-timer
    meson compile -C build
    meson devenv -C build glance-timer

test:
    meson test -C build
