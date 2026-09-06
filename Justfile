run:
    -pkill -x glance
    meson compile -C build
    meson devenv -C build glance

test:
    meson test -C build
