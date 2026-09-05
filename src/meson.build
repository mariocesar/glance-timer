config_vala = configure_file(input: 'config.vala.in', output: 'config.vala', configuration: conf)

glance = executable('glance',
  'application.vala',
  'timer-window.vala',
  config_vala,
  resources,
  dependencies: [
    dependency('glib-2.0', version: '>= 2.80'),
    dependency('gio-2.0', version: '>= 2.80'),
    dependency('gtk4', version: '>= 4.20'),
  ],
  install: true,
)
