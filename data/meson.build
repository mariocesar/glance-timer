datadir = get_option('datadir')

resources = gnome.compile_resources('glance-resources',
  configure_file(input: 'glance.gresource.xml.in', output: 'glance.gresource.xml', configuration: conf),
  source_dir: meson.current_source_dir(),
  c_name: 'glance',
)

desktop_file = configure_file(
  input: 'glance.desktop.in',
  output: app_id + '.desktop',
  configuration: conf,
  install_dir: datadir / 'applications',
)

metainfo_file = configure_file(
  input: 'glance.metainfo.xml.in',
  output: app_id + '.metainfo.xml',
  configuration: conf,
  install_dir: datadir / 'metainfo',
)

schema_file = configure_file(
  input: 'glance.gschema.xml.in',
  output: app_id + '.gschema.xml',
  configuration: conf,
  install_dir: datadir / 'glib-2.0' / 'schemas',
)

# Compiled into the build dir so `meson devenv` runs work without installing.
custom_target('gschemas',
  input: schema_file,
  output: 'gschemas.compiled',
  command: [find_program('glib-compile-schemas'), '--strict', '--targetdir', meson.current_build_dir(), meson.current_build_dir()],
  build_by_default: true,
)

devenv = environment()
devenv.set('GSETTINGS_SCHEMA_DIR', meson.current_build_dir())
meson.add_devenv(devenv)

install_data('icons/glance.svg',
  rename: app_id + '.svg',
  install_dir: datadir / 'icons' / 'hicolor' / 'scalable' / 'apps',
)
