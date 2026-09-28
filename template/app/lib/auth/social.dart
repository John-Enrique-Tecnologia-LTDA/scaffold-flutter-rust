import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../models/account.dart';
import '../platform/platform.dart';
import 'session.dart';

/// Um provedor de entrada: o que vai na URL e o nome que aparece.
enum SocialProvider {
  google('Google'),
  discord('Discord');

  final String label;
  const SocialProvider(this.label);

  static SocialProvider? parse(String? name) => values.where((p) => p.name == name).firstOrNull;
}

/// Como terminou uma entrada pelo provedor: entrou, desistiu, ou o motivo da falha.
sealed class SocialOutcome {
  const SocialOutcome();
}

class SocialSignedIn extends SocialOutcome {
  /// Para onde a pessoa ia antes do login (só na web, que sai e volta).
  final String? from;
  const SocialSignedIn(this.from);
}

class SocialCanceled extends SocialOutcome {
  const SocialCanceled();
}

class SocialFailed extends SocialOutcome {
  final String message;
  const SocialFailed(this.message);
}

/// Entrar com Google ou com Discord (server/src/oauth.rs). O app cria um segredo, manda o SHA-256
/// dele ao começar e o segredo em si ao terminar: a entrada devolvida pelo provedor só vale para
/// quem começou.
///
/// Na web a página vai ao servidor e volta em `/login?oauth=`, então o segredo (e para onde a
/// pessoa ia) esperam no armazenamento local. No Android a entrada roda numa aba do Chrome sobre
/// o app e o resultado volta na mesma chamada. O Discord no Android, com o app dele instalado, é
/// autorizado no app do Discord (já logado, sem senha): a volta chega como link
/// `discord-{id}:/authorize/callback` e cai na rota `/authorize/callback` ([resumeDiscordApp]).
class SocialSignIn {
  static const _kVerifier = '{= name =}.oauth.verifier';
  static const _kFrom = '{= name =}.oauth.from';
  static const _kProvider = '{= name =}.oauth.provider';

  /// Na web, o provedor da entrada que saiu desta aba e ainda não voltou.
  static SocialProvider? get pending => SocialProvider.parse(localRead(_kProvider));

  static String _newVerifier() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static String _challenge(String verifier) => base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');

  /// Começa a entrada. Na web a página sai daqui e o resultado chega por [resume]; no Android,
  /// devolve o resultado.
  static Future<SocialOutcome?> start(SocialProvider p, {String? from}) async {
    final verifier = _newVerifier();
    if (!kIsWeb && p == SocialProvider.discord) {
      try {
        final url = await ApiClient.instance.discordAppStart(_challenge(verifier));
        _remember(verifier, from, p);
        if (await openInOtherApp(url, package: 'com.discord')) return null;
      } catch (e) {
        debugPrint('app do Discord não abriu: $e');
      }
      // sem o app do Discord: pela aba do Chrome, logo abaixo
    }
    final url = ApiClient.instance.oauthStartUrl(p.name, platform: kIsWeb ? 'web' : 'android', challenge: _challenge(verifier));
    if (kIsWeb) {
      _remember(verifier, from, p);
      await openSignIn(url);
      return null;
    }
    final String? back;
    try {
      back = await openSignIn(url);
    } catch (e) {
      debugPrint('aba de entrada não abriu: $e');
      return SocialFailed('Não deu para abrir a entrada pelo ${p.label}. Tente de novo ou entre pelo link do email.');
    }
    if (back == null) return const SocialCanceled();
    final q = Uri.parse(back).queryParameters;
    return _complete(p, token: q['oauth'], error: q['erro'], verifier: verifier, from: from);
  }

  /// Guarda o que a volta vai precisar quando ela não chega pela mesma chamada.
  static void _remember(String verifier, String? from, SocialProvider p) {
    localWrite(_kVerifier, verifier);
    localWrite(_kFrom, from ?? '');
    localWrite(_kProvider, p.name);
  }

  /// Lê e apaga o que [_remember] guardou.
  static ({String verifier, String? from, SocialProvider provider}) _recall() {
    final verifier = localRead(_kVerifier) ?? '';
    final from = localRead(_kFrom);
    final p = SocialProvider.parse(localRead(_kProvider)) ?? SocialProvider.google;
    localWrite(_kVerifier, '');
    localWrite(_kFrom, '');
    localWrite(_kProvider, '');
    return (verifier: verifier, from: from == null || from.isEmpty ? null : from, provider: p);
  }

  /// Na web, a volta do provedor em `/login?oauth=` (ou `?erro=`).
  static Future<SocialOutcome> resume({String? token, String? error}) async {
    final r = _recall();
    if (token != null && r.verifier.isEmpty) {
      return const SocialFailed('A entrada começou em outro navegador. Tente de novo por aqui.');
    }
    return _complete(r.provider, token: token, error: error, verifier: r.verifier, from: r.from);
  }

  /// A volta do app do Discord no Android, em `/authorize/callback?code=&state=` (ou `?error=`).
  static Future<SocialOutcome> resumeDiscordApp({String? code, String? state, String? error}) async {
    const p = SocialProvider.discord;
    final r = _recall();
    if (code == null || state == null) return error == 'access_denied' ? const SocialCanceled() : SocialFailed(_message(p, 'falhou'));
    if (r.verifier.isEmpty) return SocialFailed(_message(p, 'expirou'));
    try {
      return await _signIn(await ApiClient.instance.discordAppFinish(code: code, state: state, verifier: r.verifier), r.from);
    } on Unauthenticated {
      return SocialFailed(_message(p, 'expirou'));
    } on ApiException catch (e) {
      return SocialFailed(_message(p, e.message == 'sem-email' ? 'sem-email' : 'falhou'));
    } catch (e) {
      debugPrint('entrada pelo app do Discord não terminou: $e');
      return SocialFailed(_message(p, 'falhou'));
    }
  }

  static Future<SocialOutcome> _signIn(Tokens t, String? from) async {
    final s = Session.instance;
    // outra sessão aberta neste aparelho é encerrada no servidor
    if (s.signedIn) await s.signOut();
    await s.signIn(t);
    return SocialSignedIn(from);
  }

  static Future<SocialOutcome> _complete(SocialProvider p, {String? token, String? error, required String verifier, String? from}) async {
    if (token == null || token.isEmpty) return error == 'cancelado' ? const SocialCanceled() : SocialFailed(_message(p, error));
    try {
      return await _signIn(await ApiClient.instance.finishOAuth(token, verifier), from);
    } on Unauthenticated {
      return SocialFailed(_message(p, 'expirou'));
    } catch (e) {
      debugPrint('entrada pelo ${p.name} não terminou: $e');
      return SocialFailed(_message(p, 'falhou'));
    }
  }

  static String _message(SocialProvider p, String? error) => switch (error) {
    'expirou' => 'A entrada pelo ${p.label} demorou demais e venceu. Tente de novo.',
    'sem-email' => 'A sua conta do ${p.label} não tem um email verificado. Verifique o email lá, ou entre pelo link do email aqui.',
    _ => 'Não deu para entrar pelo ${p.label} agora. Tente de novo ou entre pelo link do email.',
  };
}
