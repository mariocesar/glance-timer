# Handled locally before GTK starts. Blank displays make a regression fail fast instead of opening a window.
test('cli-version', glance, args: ['--version'], suite: 'app', timeout: 10,
  env: {'WAYLAND_DISPLAY': '', 'DISPLAY': ''})

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
