import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../auth/session.dart';
import '../widgets/auth_frame.dart';
import '../widgets/feedback.dart';

/// Destino do link do email de entrada (`/entrar?token=`). Troca o token por uma sessão e segue
/// para o app; o token some da barra de endereço porque a tela navega para outra rota ao
/// terminar.
class LinkScreen extends StatefulWidget {
  final String? token;
  const LinkScreen({super.key, this.token});
  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  final _session = Session.instance;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final token = widget.token;
    if (token == null || token.isEmpty) return setState(() => _error = 'Esse link está incompleto. Copie o endereço inteiro do email.');
    setState(() => _error = null);
    try {
      final t = await ApiClient.instance.verify(token);
      // um link novo com outra sessão aberta: a anterior é encerrada no servidor
      if (_session.signedIn) await _session.signOut();
      await _session.signIn(t);
      await _session.refreshMe();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e) {
            Unauthenticated() => 'Esse link já foi usado ou venceu. Peça outro.',
            ApiException(:final message) => 'Não deu para abrir o link: $message.',
            _ => 'Sem conexão com o servidor. Tente de novo.',
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error == null) {
      return AuthFrame(
        children: [
          const SizedBox(height: 8),
          const LoadingState(),
          const SizedBox(height: 20),
          Text('Entrando…', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ],
      );
    }
    return AuthFrame(
      children: [
        Text('Link de entrada', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        InlineNotice(_error!),
        const SizedBox(height: 20),
        if (_session.signedIn)
          FilledButton(onPressed: () => context.go('/'), child: const Text('Ir para o app'))
        else
          FilledButton(onPressed: () => context.go('/login'), child: const Text('Pedir um link novo')),
      ],
    );
  }
}
