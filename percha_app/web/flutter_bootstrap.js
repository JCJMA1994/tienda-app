// Plantilla de arranque (Flutter 3.22+): `flutter build web` reemplaza las dos marcas.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    // La app ya pintó: se quita la pantalla de carga.
    document.getElementById('splash')?.remove();
  },
});
