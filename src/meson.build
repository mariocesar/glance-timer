config_vala = configure_file(input: 'config.vala.in', output: 'config.vala', configuration: conf)

# GTK-free core, shared with the unit tests.
core_sources = files('deadline.vala', 'duration.vala', 'timer.vala')
core_deps = [
  dependency('glib-2.0', version: '>= 2.80'),
  dependency('gobject-2.0', version: '>= 2.80'),
  meson.get_compiler('vala').find_library('posix'),
]

picker_sources = files('duration-picker.vala')

glance = executable('glance',
  'application.vala',
  picker_sources,
  'timer-window.vala',
  core_sources,
  config_vala,
  resources,
  dependencies: core_deps + [
    dependency('gio-2.0', version: '>= 2.80'),
    dependency('gtk4', version: '>= 4.20'),
  ],
  install: true,
)
