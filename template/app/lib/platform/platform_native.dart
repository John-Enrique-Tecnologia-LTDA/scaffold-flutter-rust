import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

SharedPreferences? _prefs;
bool _fullscreen = false;

/// Carrega as preferências antes do primeiro quadro, para o guardado local ser síncrono.
Future<void> initPlatform() async {
  _prefs = await SharedPreferences.getInstance();
}

/// O app está em primeiro plano (antes do primeiro aviso do sistema, vale à mostra).
bool get pageVisible {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// Chama [onChange] quando o app vai para o primeiro plano ou sai dele; devolve o que desliga.
void Function() onVisibilityChange(void Function() onChange) {
  var visible = pageVisible;
  final listener = AppLifecycleListener(
    onStateChange: (_) {
      if (pageVisible == visible) return;
      visible = pageVisible;
      onChange();
    },
  );
  return listener.dispose;
}

bool get isFullscreen => _fullscreen;

/// Devolve as barras do sistema, se estiverem escondidas.
void exitFullscreen() {
  if (_fullscreen) toggleFullscreen();
}

/// Esconde (ou devolve) as barras do sistema. Os recuos do [SafeArea] seguem: sem a barra de
/// navegação, o espaço dela some (o da câmera fica).
void toggleFullscreen() {
  _fullscreen = !_fullscreen;
  SystemChrome.setEnabledSystemUIMode(_fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
}

/// Entrar pelo Google ou pelo Discord: uma aba do Chrome sobre o app, que fecha sozinha quando o
/// servidor devolve o app pelo esquema dele (`{= android_id =}://oauth?…`). Devolve esse
/// endereço, ou `null` se a pessoa fechou a aba.
Future<String?> openSignIn(String url) async {
  try {
    return await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: '{= android_id =}');
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') return null;
    rethrow;
  }
}

const _apps = MethodChannel('{= name =}/apps');

/// Abre o link no app do pacote `package` (o do Discord, para autorizar a entrada), mesmo que ele
/// não esteja marcado para abrir os links dele; `false` se o app não está instalado.
Future<bool> openInOtherApp(String url, {required String package}) async {
  try {
    return await _apps.invokeMethod<bool>('openIn', {'url': url, 'package': package}) ?? false;
  } catch (_) {
    return false;
  }
}

/// Abre o link no navegador do aparelho.
void openExternal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

String? localRead(String key) => _prefs?.getString(key);

void localWrite(String key, String value) => _prefs?.setString(key, value);
