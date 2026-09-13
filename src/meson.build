config_vala = configure_file(input: 'config.vala.in', output: 'config.vala', configuration: conf)

# GTK-free core, shared with the unit tests.
core_sources = files('deadline.vala', 'duration.vala', 'timer.vala')
core_deps = [
  dependency('glib-2.0', version: '>= 2.80'),
  dependency('gobject-2.0', version: '>= 2.80'),
  meson.get_compiler('vala').find_library('posix'),
]

picker_sources = files('duration-picker.vala')
# Everything but main(), shared with the widget tests.
app_sources = [files('application.vala', 'timer-window.vala'), picker_sources, core_sources, config_vala, resources]
app_deps = core_deps + [dependency('gstreamer-1.0'), 
  dependency('gio-2.0', version: '>= 2.80'),
  dependency('gtk4', version: '>= 4.20'),
]

glance = executable('glance', 'main.vala', app_sources, dependencies: app_deps, install: true)
