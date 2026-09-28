import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import 'format.dart';
import 'theme.dart';

/// O erro como a pessoa deve ler: a mensagem do servidor quando é culpa do pedido, e uma frase
/// sobre a conexão quando o servidor não respondeu. Nada de "ClientException" na tela.
String describeError(Object e) => switch (e) {
  ApiException(:final status, :final message) when status < 500 => sentence(message),
  ApiException() => 'O servidor falhou agora. Tente de novo em instantes.',
  Unauthenticated() => 'A sessão acabou. Entre de novo.',
  TimeoutException() => 'O servidor demorou demais para responder. Tente de novo.',
  http.ClientException() => 'Sem conexão com o servidor. Tente de novo.',
  _ => sentence('$e'),
};

/// Aviso inline (sem toast, por decisão de produto): erro em vermelho, informação em neutro.
/// Com `onClose`, ganha o botão de dispensar.
class InlineNotice extends StatelessWidget {
  final String text;
  final bool error;
  final VoidCallback? onClose;
  const InlineNotice(this.text, {super.key, this.error = true, this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = error ? Palette.danger : scheme.primary;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, onClose == null ? 12 : 4, 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(error ? Icons.error_outline : Icons.check_circle_outline, size: 18, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(padding: const EdgeInsets.only(top: 1), child: Text(text)),
          ),
          if (onClose != null)
            SizedBox(
              width: 28,
              height: 22,
              child: IconButton(padding: EdgeInsets.zero, iconSize: 16, tooltip: 'Dispensar', onPressed: onClose, icon: const Icon(Icons.close)),
            ),
        ],
      ),
    );
  }
}

/// Os avisos de erro e de sucesso de uma tela, um embaixo do outro, cada um dispensável.
class NoticeStack extends StatelessWidget {
  final String? error, info;
  final VoidCallback onClearError, onClearInfo;
  final EdgeInsets padding;
  const NoticeStack({super.key, this.error, this.info, required this.onClearError, required this.onClearInfo, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    if (error == null && info == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) InlineNotice(error!, onClose: onClearError),
          if (error != null && info != null) const SizedBox(height: 8),
          if (info != null) InlineNotice(info!, error: false, onClose: onClearInfo),
        ],
      ),
    );
  }
}

/// Tela vazia com cara de tela: ícone num halo, título, explicação e, se houver, o próximo passo.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? color;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.02)]),
                  border: Border.all(color: tint.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, size: 36, color: tint),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Falha ao carregar a tela, com o motivo legível e o botão de tentar de novo.
class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    color: Palette.danger,
    title: 'Não deu para carregar',
    message: error is String ? error as String : describeError(error),
    action: FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Tentar de novo')),
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)));
}

/// Ícone de progresso do tamanho de um ícone de botão.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
}
