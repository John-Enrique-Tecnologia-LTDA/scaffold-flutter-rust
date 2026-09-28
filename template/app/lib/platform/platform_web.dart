import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Nada a preparar na web.
Future<void> initPlatform() async {}

/// A aba está à mostra.
bool get pageVisible => web.document.visibilityState == 'visible';

/// Chama [onChange] quando a aba aparece ou some; devolve o que desliga o aviso.
void Function() onVisibilityChange(void Function() onChange) {
  final listener = ((web.Event _) => onChange()).toJS;
  web.document.addEventListener('visibilitychange', listener);
  return () => web.document.removeEventListener('visibilitychange', listener);
}

bool get isFullscreen => web.document.fullscreenElement != null;

/// Sai da tela cheia, se estiver nela.
void exitFullscreen() {
  if (isFullscreen) web.document.exitFullscreen();
}

void toggleFullscreen() {
  final d = web.document;
  if (d.fullscreenElement != null) {
    d.exitFullscreen();
  } else {
    d.documentElement?.requestFullscreen();
  }
}

/// Entrar pelo Google ou pelo Discord: a aba vai ao servidor, passa pelo provedor e volta em
/// `/login?oauth=` (ou `?erro=`). A página sai daqui; nada volta por esta chamada.
Future<String?> openSignIn(String url) async {
  web.window.location.assign(url);
  return null;
}

/// Só no Android: na web não há outro app para abrir.
Future<bool> openInOtherApp(String url, {required String package}) async => false;

/// Abre o link numa aba nova.
void openExternal(String url) => web.window.open(url, '_blank');

String? localRead(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void localWrite(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}
