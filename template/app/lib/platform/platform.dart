/// O pouco que muda entre o navegador e o app Android: se a tela está à mostra, tela cheia, abrir
/// link fora do app e um guardado local síncrono. Na web é a API do navegador; no Android, o
/// ciclo de vida do app, a interface do sistema e as preferências.
library;

export 'platform_native.dart' if (dart.library.js_interop) 'platform_web.dart';
