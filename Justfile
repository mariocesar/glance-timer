run:
    -pkill -x glance-timer
    meson compile -C build
    meson devenv -C build glance-timer

test:
    meson test -C build

# Retake the README screenshots. niri only; opens Glance on this desktop for a few seconds.
screenshots:
    #!/usr/bin/env bash
    set -euo pipefail
    meson compile -C build
    pkill -x glance-timer || true
    export GSETTINGS_SCHEMA_DIR=build/data GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME=$(mktemp -d)
    gsettings set io.github.mariocesar.Glance alarm-volume 0
    app=build/src/glance-timer
    wait_for() { timeout 10 sh -c 'until [ -s "$0" ]; do sleep 0.2; done' "$1"; }
    shot() {
        rm -f "$1"
        sleep 1
        id=$(niri msg --json windows | jq '.[] | select(.app_id == "io.github.mariocesar.Glance") | .id' | head -1)
        niri msg action screenshot-window --id "$id" --path "$1"
        wait_for "$1"
    }
    $app & sleep 1
    shot "$PWD/screenshots/setup.png"
    $app 25m --label "Write the report"; shot "$PWD/screenshots/running.png"
    $app --pause; shot "$PWD/screenshots/paused.png"
    $app 2s --label "Tea is ready"; sleep 2; shot "$PWD/screenshots/finished.png"
    # Peek is a layer surface, not a window: cut it out of the screen by its background colour.
    $app 25m --label "Write the report"; $app --peek; sleep 1
    screen=$(mktemp -u --suffix .png)
    niri msg action screenshot-screen --path "$screen"
    wait_for "$screen"
    magick "$screen" -gravity NorthEast -crop 50%x50%+0+0 +repage "$screen"
    box=$(magick "$screen" -fill black +opaque '#15171b' -format '%@' info:)
    magick "$screen" -crop "$box" +repage screenshots/peek.png
    pkill -x glance-timer || true
    oxipng -o 4 --strip safe screenshots/*.png
