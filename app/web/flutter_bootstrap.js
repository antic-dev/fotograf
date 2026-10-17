{{flutter_js}}
{{flutter_build_config}}

// Bez inline skripti (stroga Content-Security-Policy).
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const splash = document.getElementById('splash');
    if (splash) {
      splash.classList.add('hide');
      setTimeout(function () { splash.remove(); }, 400);
    }
  },
});
