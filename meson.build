project('glance', ['c', 'vala'],
  version: '0.1.0',
  license: 'MIT',
  license_files: 'LICENSE',
  meson_version: '>= 1.4',
  default_options: ['warning_level=1', 'buildtype=debugoptimized', 'werror=true'],
)

app_id = 'io.github.mariocesar.Glance'

gnome = import('gnome')

# valac warnings are the quality gate (distro builds pass -Dwerror=false); warnings in generated C are not actionable.
if get_option('werror')
  add_project_arguments('--fatal-warnings', language: 'vala')
endif
add_project_arguments('-w', language: 'c')

conf = configuration_data()
conf.set('APP_ID', app_id)
conf.set('VERSION', meson.project_version())
conf.set('HOMEPAGE', 'https://github.com/mariocesar/glance-timer')
conf.set('RESOURCE_PATH', '/' + app_id.replace('.', '/'))

subdir('data')
subdir('src')
subdir('tests')

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
