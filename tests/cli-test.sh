#!/bin/sh
# End-to-end CLI test: a real primary instance and forwarded commands, on a private D-Bus session
# and GTK's headless Broadway display so nothing reaches the user's desktop or running Glance.
# Usage: sh cli-test.sh path/to/glance
GLANCE=$1
command -v gtk4-broadwayd >/dev/null || { echo "gtk4-broadwayd not found"; exit 77; }
command -v dbus-run-session >/dev/null || { echo "dbus-run-session not found"; exit 77; }

# Re-run inside a private bus with a private runtime directory. Services the bus activates
# (the accessibility bus in particular) would otherwise replace sockets under the user's
# /run/user/UID and break them for the whole desktop session when the test ends.
if [ -z "$GLANCE_TEST_ISOLATED" ]; then
    runtime=$(mktemp -d)
    chmod 700 "$runtime"
    GLANCE_TEST_ISOLATED=1 XDG_RUNTIME_DIR=$runtime GIO_USE_VFS=local GDK_DEBUG=no-portals NO_AT_BRIDGE=1 \
        dbus-run-session -- sh "$0" "$@"
    code=$?
    rm -rf "$runtime"
    exit $code
fi
display=:$(( $$ % 60 + 30 ))
gtk4-broadwayd "$display" >/dev/null 2>&1 &
broadway=$!
trap 'kill $primary $broadway 2>/dev/null' EXIT
# GTK_A11Y=none: on Broadway GTK picks its test accessibility backend, which crashes in announce ().
export GDK_BACKEND=broadway BROADWAY_DISPLAY=$display GSETTINGS_BACKEND=memory GTK_A11Y=none
sleep 0.5
failed=0

# expect CODE PATTERN ARGS...: an empty PATTERN means the command must print nothing.
expect() {
    code=$1; pattern=$2; shift 2
    out=$("$GLANCE" "$@" 2>&1); got=$?
    if [ -z "$pattern" ]; then matched=$([ -z "$out" ] && echo y); else matched=$(printf '%s' "$out" | grep -q -- "$pattern" && echo y); fi
    if [ "$got" -ne "$code" ] || [ -z "$matched" ]; then
        echo "FAIL: glance $* -> exit $got, output: $out (wanted exit $code and /$pattern/)"; failed=1
    else
        echo "ok: glance $*"
    fi
}

owned() {
    gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner io.github.mariocesar.Glance | grep -q true
}

expect 0 "--until" --help
expect 0 "[0-9]" --version
expect 1 "no timer is running" --pause
expect 1 "no timer is running" --stop
owned && { echo "FAIL: a remote action with no instance left a process behind"; failed=1; }

"$GLANCE" 10m --label Review &
primary=$!
for i in $(seq 50); do owned && break; sleep 0.1; done
owned || { echo "FAIL: primary never registered"; exit 1; }

expect 0 "" --pause
expect 1 "already paused" --pause
expect 0 "" --resume
expect 1 "not paused" --resume
expect 0 "" --add 5m
expect 0 "" --reset
expect 0 "" 1h 25m
expect 0 "" --until 23:59
expect 1 "can't be paused" --pause
expect 1 "can't be restarted" --reset
expect 0 "" --hide
kill -0 $primary 2>/dev/null || { echo "FAIL: hiding a running timer quit the app"; failed=1; }
expect 0 "" --show
expect 1 "layer-shell" --pin
expect 0 "" --window
expect 0 "" --hide
expect 0 "" --stop
for i in $(seq 30); do kill -0 $primary 2>/dev/null || break; sleep 0.1; done
kill -0 $primary 2>/dev/null && { echo "FAIL: stopping with the window hidden did not quit"; failed=1; }
owned && { echo "FAIL: name still owned after quit"; failed=1; }
exit $failed
