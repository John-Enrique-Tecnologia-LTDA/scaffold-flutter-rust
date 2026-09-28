import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../auth/session.dart';
import '../auth/social.dart';
import '../widgets/auth_frame.dart';
import '../widgets/brand_logos.dart';
import '../widgets/feedback.dart';
import '../widgets/legal.dart';

/// Entrada sem senha: com a conta do Google ou do Discord (os que o servidor tiver ligados), ou
/// pelo email, com um link que vale por 15 minutos.
///
/// O link costuma abrir em outra aba (ou, no Android, no app). Enquanto espera, esta tela relê
/// o armazenamento a cada dois segundos: quando a outra aba entra, esta entra junto. Na web, a
/// volta do Google ou do Discord também cai aqui (`/login?oauth=` ou `?erro=`).
class LoginScreen extends StatefulWidget {
  final String? notice;

  /// Para onde a pessoa ia antes de cair no login.
  final String? from;

  /// A volta do provedor, na web.
  final String? oauthToken, oauthError;

  /// A volta do app do Discord, no Android (`/authorize/callback`).
  final ({String? code, String? state, String? error})? discordApp;
  const LoginScreen({super.key, this.notice, this.from, this.oauthToken, this.oauthError, this.discordApp});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;
  Timer? _watch;

  /// Os provedores ligados no servidor; vazio se não há nenhum (ou não deu para saber).
  List<SocialProvider> _providers = const [];

  /// O provedor cuja entrada está em andamento.
  SocialProvider? _social;

  @override
  void initState() {
    super.initState();
    _error = widget.notice;
    _loadProviders();
    if (_returning) WidgetsBinding.instance.addPostFrameCallback((_) => _resume());
  }

  Future<void> _loadProviders() async {
    try {
      final names = await ApiClient.instance.authProviders();
      if (mounted) setState(() => _providers = [for (final n in names) ?SocialProvider.parse(n)]);
    } catch (_) {
      // sem a lista, fica só o email
    }
  }

  /// Esta tela é a volta de um provedor (e não o login aberto do zero).
  bool get _returning => widget.oauthToken != null || widget.oauthError != null || widget.discordApp != null;

  Future<void> _signInWith(SocialProvider p) async {
    setState(() {
      _social = p;
      _error = null;
    });
    final outcome = await SocialSignIn.start(p, from: widget.from);
    if (outcome != null) {
      await _finish(outcome);
    } else if (mounted && !kIsWeb) {
      // o app do Discord abriu por cima; a volta chega por outra rota, e quem desistir lá encontra
      // o login livre
      setState(() => _social = null);
    }
  }

  Future<void> _resume() async {
    setState(() => _social = SocialSignIn.pending ?? SocialProvider.google);
    final d = widget.discordApp;
    await _finish(
      d != null
          ? await SocialSignIn.resumeDiscordApp(code: d.code, state: d.state, error: d.error)
          : await SocialSignIn.resume(token: widget.oauthToken, error: widget.oauthError),
    );
  }

  Future<void> _finish(SocialOutcome outcome) async {
    if (!mounted) return;
    switch (outcome) {
      case SocialSignedIn(:final from):
        // a volta da web perdeu o `from` da barra de endereço: o roteador segue para lá depois
        if (from != null) context.go(Uri(path: '/login', queryParameters: {'from': from}).toString());
        try {
          await Session.instance.refreshMe(); // o roteador sai do login sozinho
        } catch (_) {}
      case SocialCanceled():
        setState(() => _social = null);
        if (_returning) context.go('/login');
      case SocialFailed(:final message):
        // tira o `?oauth=` da barra de endereço, levando a mensagem
        if (_returning) {
          context.go('/login', extra: message);
        } else {
          setState(() {
            _social = null;
            _error = message;
          });
        }
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send([String? again]) async {
    final email = (again ?? _email.text).trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Digite o seu email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.requestMagicLink(email);
      if (!mounted) return;
      setState(() => _sentTo = email);
      _watch ??= Timer.periodic(const Duration(seconds: 2), (_) => _checkOtherTab());
    } catch (e) {
      // 5xx aqui é quase sempre o envio do email que falhou
      if (mounted) {
        setState(() => _error = e is ApiException && e.status >= 500 ? 'Não deu para mandar o email agora. Tente de novo em instantes.' : describeError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A conta de demonstração (revisão da Play Store) entra com email e código, sem o email.
  Future<void> _accessCode() async {
    final r = await showDialog<(String, String)>(context: context, builder: (_) => const _AccessCodeDialog());
    if (r == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await ApiClient.instance.accessCode(r.$1, r.$2);
      await Session.instance.signIn(t);
      await Session.instance.refreshMe(); // o roteador sai do login sozinho
    } catch (e) {
      if (mounted) setState(() => _error = e is Unauthenticated ? 'Email ou código de acesso não conferem.' : describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOtherTab() async {
    final s = Session.instance;
    if (!await s.reloadTokens() || !s.signedIn) return;
    _watch?.cancel();
    try {
      await s.refreshMe(); // o roteador sai do login sozinho
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_sentTo != null) {
      return AuthFrame(
        children: [
          Center(child: Icon(Icons.mark_email_read_outlined, size: 48, color: theme.colorScheme.primary)),
          const SizedBox(height: 12),
          Text(
            'Confira o seu email',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Mandamos um link de entrada para '),
                TextSpan(
                  text: _sentTo,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '. Ele vale por 15 minutos e só funciona uma vez.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Pode abrir o link em outra aba: quando você entrar por lá, esta tela entra junto.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_error != null) ...[const SizedBox(height: 16), InlineNotice(_error!)],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(onPressed: _busy ? null : () => _send(_sentTo), icon: const Icon(Icons.refresh), label: const Text('Mandar de novo')),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        _watch?.cancel();
                        _watch = null;
                        setState(() {
                          _sentTo = null;
                          _error = null;
                        });
                      },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Usar outro email'),
              ),
            ],
          ),
        ],
      );
    }
    final busy = _busy || _social != null;
    return AuthFrame(
      children: [
        Text('Entrar', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          _providers.isEmpty
              ? 'Sem senha: mandamos um link para o seu email. Se ainda não tem conta, ela é criada na primeira entrada.'
              : 'Sem senha: com a sua conta do ${_providers.map((p) => p.label).join(' ou do ')}, ou com um link no seu email. Se ainda não tem conta, ela é criada na primeira entrada.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        if (_providers.isNotEmpty) ...[
          for (final p in _providers) ...[
            _SocialButton(provider: p, busy: _social == p, onPressed: busy ? null : () => _signInWith(p)),
            const SizedBox(height: 10),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ou pelo email', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        AutofillGroup(
          child: TextField(
            controller: _email,
            // no celular o teclado cobriria os botões dos provedores
            autofocus: MediaQuery.sizeOf(context).width >= 600,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.send,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
            onSubmitted: (_) => _send(),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), InlineNotice(_error!)],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : _send,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          icon: _busy ? const ButtonSpinner() : const Icon(Icons.send_outlined),
          label: const Text('Receber link de entrada'),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(onPressed: busy ? null : _accessCode, child: const Text('Tenho um código de acesso')),
        ),
        const SizedBox(height: 8),
        const LegalLinks(),
      ],
    );
  }
}

/// Email e código de acesso da conta de demonstração.
class _AccessCodeDialog extends StatefulWidget {
  const _AccessCodeDialog();
  @override
  State<_AccessCodeDialog> createState() => _AccessCodeDialogState();
}

class _AccessCodeDialogState extends State<_AccessCodeDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_email.text.trim().isEmpty || _code.text.trim().isEmpty) return;
    Navigator.pop(context, (_email.text.trim(), _code.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Código de acesso'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Código'),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _submit, child: const Text('Entrar')),
    ],
  );
}

/// "Continuar com o Google" e "Continuar com o Discord", nas cores de cada marca: o do Google no
/// tema escuro das diretrizes dele, o do Discord no azul da marca.
class _SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final bool busy;
  final VoidCallback? onPressed;
  const _SocialButton({required this.provider, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final google = provider == SocialProvider.google;
    final fg = google ? const Color(0xFFE3E3E3) : Colors.white;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: google ? const Color(0xFF131314) : discordBlurple,
        foregroundColor: fg,
        disabledBackgroundColor: (google ? const Color(0xFF131314) : discordBlurple).withValues(alpha: 0.5),
        disabledForegroundColor: fg.withValues(alpha: 0.7),
        side: google ? const BorderSide(color: Color(0xFF8E918F)) : BorderSide.none,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          else
            google ? const GoogleLogo() : const DiscordLogo(),
          const SizedBox(width: 12),
          Text('Continuar com o ${provider.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
