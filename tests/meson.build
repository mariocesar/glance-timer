# Handled locally before GTK starts. Blank displays make a regression fail fast instead of opening a window.
test('cli-version', glance, args: ['--version'], suite: 'app', timeout: 10,
  env: {'WAYLAND_DISPLAY': '', 'DISPLAY': ''})

# A real primary instance plus forwarded commands, isolated on a private bus and a headless display.
dbus_run_session = find_program('dbus-run-session', required: false)
if dbus_run_session.found()
  test('cli', dbus_run_session, args: ['--', 'sh', files('cli-test.sh'), glance], suite: 'app', timeout: 60,
    depends: gschemas, env: {'GSETTINGS_SCHEMA_DIR': meson.project_build_root() / 'data'})
endif

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
  test('desktop-file', desktop_file_validate, args: [desktop_file], suite: 'data')
endif

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
  test('metainfo', appstreamcli, args: ['validate', '--no-net', metainfo_file], suite: 'data')
endif

timer_test = executable('timer-test', 'timer-test.vala', core_sources, dependencies: core_deps)
test('timer', timer_test, suite: 'unit', protocol: 'tap', args: ['--tap'])

foreach name : ['parser', 'deadline']
  exe = executable(name + '-test', name + '-test.vala', core_sources, dependencies: core_deps)
  test(name, exe, suite: 'unit', protocol: 'tap', args: ['--tap'])
endforeach

# Needs a display; skips itself without one. Settings stay in memory, never in the user's dconf.
foreach name : ['picker', 'window']
  exe = executable(name + '-test', name + '-test.vala', app_sources, dependencies: app_deps)
  test(name, exe, suite: 'widget', protocol: 'tap', args: ['--tap'], depends: gschemas,
    env: {'GSETTINGS_SCHEMA_DIR': meson.project_build_root() / 'data', 'GSETTINGS_BACKEND': 'memory'})
endforeach
