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
