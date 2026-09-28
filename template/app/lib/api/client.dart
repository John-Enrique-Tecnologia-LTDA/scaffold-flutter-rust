import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/session.dart';
import '../models/account.dart';
{% for e in entities %}import '../models/{= e.name =}.dart';
{% endfor %}
class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// A sessão morreu no servidor (saiu, refresh reusado ou vencido): o app volta ao login.
class Unauthenticated implements Exception {
  @override
  String toString() => 'sessão encerrada; entre de novo';
}

/// Cliente HTTP da API. Na web usa a mesma origem (o nginx, ou o servidor Rust em
/// desenvolvimento); no `flutter run` e no app Android, a API de produção. `--dart-define=API_BASE=`
/// aponta outra.
///
/// Toda chamada leva o JWT de acesso. Num 401 tenta UMA renovação (dividida entre as chamadas
/// simultâneas) e repete; se a renovação também falha, a sessão acabou.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _production = 'https://{= domain =}';
  static const _override = String.fromEnvironment('API_BASE');
  final String base = _override.isNotEmpty
      ? _override
      : kIsWeb && (Uri.base.port == 8080 || Uri.base.host != 'localhost')
      ? Uri.base.origin
      : _production;

  Session get _session => Session.instance;
  Future<bool>? _refreshing;

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base$path').replace(queryParameters: q);

  Map<String, String> _headers({bool json = false}) => {
    if (json) 'content-type': 'application/json',
    if (_session.accessToken != null) 'authorization': 'Bearer ${_session.accessToken}',
  };

  Future<http.Response> _raw(String method, String path, {Object? body, Map<String, String>? q}) {
    final req = http.Request(method, _u(path, q))..headers.addAll(_headers(json: body != null));
    if (body != null) req.body = jsonEncode(body);
    return req.send().then(http.Response.fromStream).timeout(const Duration(seconds: 120));
  }

  ApiException _error(http.Response r) {
    String msg = 'HTTP ${r.statusCode}';
    try {
      msg = jsonDecode(utf8.decode(r.bodyBytes))['error'] ?? msg;
    } catch (_) {}
    return ApiException(r.statusCode, msg);
  }

  dynamic _decode(http.Response r) => r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));

  /// Faz o pedido renovando o acesso uma vez num 401; sessão morta vira [Unauthenticated].
  Future<http.Response> _send(String method, String path, {Object? body, Map<String, String>? q}) async {
    var r = await _raw(method, path, body: body, q: q);
    if (r.statusCode == 401 && _session.signedIn) {
      if (!await _refresh()) {
        await _session.signOut(notifyServer: false);
        throw Unauthenticated();
      }
      r = await _raw(method, path, body: body, q: q);
    }
    if (r.statusCode == 401) throw Unauthenticated();
    return r;
  }

  Future<dynamic> _req(String method, String path, {Object? body, Map<String, String>? q}) async {
    final r = await _send(method, path, body: body, q: q);
    if (r.statusCode >= 400) throw _error(r);
    return _decode(r);
  }

  /// Renova o acesso. Antes relê o armazenamento: no navegador outra aba pode já ter renovado,
  /// e aí basta usar o token dela. Se o servidor diz que a troca acabou de acontecer (409),
  /// foi outra aba no mesmo instante: espera ela gravar e relê.
  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final before = _session.refreshToken;
        if (await _session.reloadTokens() && _session.refreshToken != null && _session.refreshToken != before) {
          _adoptedFromOtherTab();
          return true;
        }
        for (var attempt = 0; attempt < 3; attempt++) {
          final r = await http
              .post(_u('/api/auth/refresh'), headers: {'content-type': 'application/json'}, body: jsonEncode({'refresh_token': _session.refreshToken}))
              .timeout(const Duration(seconds: 20));
          if (r.statusCode == 200) {
            await _session.signIn(Tokens.fromJson(_decode(r)));
            return true;
          }
          if (r.statusCode != 409) return false;
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          if (await _session.reloadTokens()) {
            if (_session.refreshToken == null) return false;
            _adoptedFromOtherTab();
            return true;
          }
        }
        return false;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// A sessão que veio de outra aba pode ser de outra pessoa (ela saiu e entrou com outro
  /// email): relê quem é, depois que esta renovação terminar.
  void _adoptedFromOtherTab() => Future.microtask(() => _session.refreshMe()).catchError((_) {});

  Future<dynamic> _get(String path, [Map<String, String>? q]) => _req('GET', path, q: q);
  Future<dynamic> _json(String method, String path, Object body, [Map<String, String>? q]) => _req(method, path, body: body, q: q);
  Future<dynamic> _delete(String path, [Map<String, String>? q]) => _req('DELETE', path, q: q);

  // ---- contas ----
  Future<void> requestMagicLink(String email) => _json('POST', '/api/auth/magic-link', {'email': email});

  /// Troca o token do link por uma sessão. Link usado ou vencido vira [Unauthenticated].
  Future<Tokens> verify(String token) async {
    final r = await http.post(_u('/api/auth/verify'), headers: {'content-type': 'application/json'}, body: jsonEncode({'token': token}));
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  /// Entrada por código de acesso (a conta de demonstração da revisão da Play Store).
  Future<Tokens> accessCode(String email, String code) async {
    final r = await http.post(_u('/api/auth/access-code'), headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email, 'code': code}));
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  /// Os provedores de entrada ligados no servidor (`google`, `discord`).
  Future<List<String>> authProviders() async {
    final r = await http.get(_u('/api/auth/providers'));
    if (r.statusCode >= 400) throw _error(r);
    return [for (final p in (_decode(r)['providers'] as List)) p as String];
  }

  /// Onde começa a entrada por um provedor; `challenge` é o SHA-256 do segredo do app.
  String oauthStartUrl(String provider, {required String platform, required String challenge}) =>
      _u('/api/auth/oauth/$provider/start', {'platform': platform, 'challenge': challenge}).toString();

  /// Troca a entrada que o provedor devolveu por uma sessão, com o segredo de quem começou.
  Future<Tokens> finishOAuth(String token, String verifier) async {
    final r = await http.post(
      _u('/api/auth/oauth/finish'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'token': token, 'verifier': verifier}),
    );
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  /// Android com o app do Discord: o endereço de autorização para abrir nele.
  Future<String> discordAppStart(String challenge) async {
    final r = await http.post(_u('/api/auth/oauth/discord/app'), headers: {'content-type': 'application/json'}, body: jsonEncode({'challenge': challenge}));
    if (r.statusCode >= 400) throw _error(r);
    return _decode(r)['url'] as String;
  }

  /// Troca o código que o app do Discord devolveu por uma sessão.
  Future<Tokens> discordAppFinish({required String code, required String state, required String verifier}) async {
    final r = await http.post(
      _u('/api/auth/oauth/discord/app/finish'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': code, 'state': state, 'verifier': verifier}),
    );
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  Future<void> logout() => _json('POST', '/api/auth/logout', {});
  Future<void> logoutAll() => _json('POST', '/api/auth/logout-all', {});
  Future<Me> me() async => Me.fromJson(await _get('/api/me'));
  Future<User> patchMe({required String name}) async => User.fromJson(await _json('PATCH', '/api/me', {'name': name}));

  /// Apaga a conta de quem está logado, com tudo o que é dela.
  Future<void> deleteAccount() => _delete('/api/me');

{% for e in entities %}  // ---- {= e.label_plural_lower =} ----
  Future<List<{= e.class =}>> {= e.camel_plural =}() async => [for (final x in await _get('/api/{= e.plural =}')) {= e.class =}.fromJson(x)];
  Future<{= e.class =}> {= e.camel =}(String id) async => {= e.class =}.fromJson(await _get('/api/{= e.plural =}/$id'));
  Future<{= e.class =}> create{= e.class =}(Map<String, dynamic> body) async => {= e.class =}.fromJson(await _json('POST', '/api/{= e.plural =}', body));
  Future<{= e.class =}> patch{= e.class =}(String id, Map<String, dynamic> patch) async => {= e.class =}.fromJson(await _json('PATCH', '/api/{= e.plural =}/$id', patch));
  Future<void> delete{= e.class =}(String id) => _delete('/api/{= e.plural =}/$id');
{% if not loop.last %}
{% endif %}{% endfor %}}
