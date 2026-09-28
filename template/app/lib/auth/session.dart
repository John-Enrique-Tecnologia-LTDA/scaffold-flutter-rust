import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
import '../models/account.dart';

/// Quem está logado neste aparelho.
///
/// Os tokens ficam no `flutter_secure_storage` (Keystore no Android; no navegador, o
/// armazenamento local cifrado). O roteador escuta esta sessão e troca de tela sozinho: sem
/// sessão vai para o login.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  static const _store = FlutterSecureStorage();
  static const _kAccess = '{= name =}.access', _kRefresh = '{= name =}.refresh';

  String? _access, _refresh;
  User? user;

  bool get signedIn => _refresh != null;
  String? get accessToken => _access;
  String? get refreshToken => _refresh;

  /// Lê o que ficou guardado e, se há sessão, confere no servidor quem é.
  Future<void> load() async {
    await reloadTokens();
    if (!signedIn) return;
    try {
      await refreshMe();
    } on Unauthenticated {
      // sessão morta no servidor: volta ao login sem alarde
    } catch (e) {
      debugPrint('sem conexão ao carregar a sessão: $e');
    }
  }

  /// Relê os tokens guardados. No navegador outra aba pode ter entrado ou renovado a sessão.
  /// Devolve true se mudou alguma coisa.
  Future<bool> reloadTokens() async {
    String? a, r;
    try {
      a = await _store.read(key: _kAccess);
      r = await _store.read(key: _kRefresh);
    } catch (e) {
      debugPrint('armazenamento seguro ilegível: $e');
    }
    final changed = a != _access || r != _refresh;
    _access = a;
    _refresh = r;
    return changed;
  }

  Future<void> signIn(Tokens t) async {
    _access = t.access;
    _refresh = t.refresh;
    user = t.user;
    await _store.write(key: _kAccess, value: t.access);
    await _store.write(key: _kRefresh, value: t.refresh);
  }

  Future<void> signOut({bool notifyServer = true}) async {
    if (notifyServer && _access != null) {
      try {
        await ApiClient.instance.logout();
      } catch (_) {}
    }
    _access = null;
    _refresh = null;
    user = null;
    try {
      await _store.delete(key: _kAccess);
      await _store.delete(key: _kRefresh);
    } catch (_) {}
    notifyListeners();
  }

  /// Recarrega /me.
  Future<void> refreshMe() async {
    final me = await ApiClient.instance.me();
    user = me.user;
    notifyListeners();
  }
}
