{{flutter_js}}
{{flutter_build_config}}

// Sem o service worker do Flutter: ele está descontinuado e, ao ativar, se desregistra e recarrega
// a página, o que deixava a instalação do PWA travada. O do {= display_name =} é o /sw.js, registrado abaixo.
_flutter.loader.load();

// primeiro quadro do app na tela: sai a logo de carregamento do index.html
window.addEventListener('flutter-first-frame', () => {
  const splash = document.getElementById('splash');
  if (!splash) return;
  splash.classList.add('out');
  setTimeout(() => splash.remove(), 400);
});

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch((e) => console.warn('service worker não registrou:', e));
  });
}
