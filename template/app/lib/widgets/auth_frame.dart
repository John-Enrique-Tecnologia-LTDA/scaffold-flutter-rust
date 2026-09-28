import 'package:flutter/material.dart';

import 'page.dart';
import 'theme.dart';

/// Moldura das telas de fora da coleção (login, link do email): o fundo escuro com um brilho
/// da marca, a marca no topo e o conteúdo num cartão estreito, centrado e rolável
/// em tela baixa.
class AuthFrame extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const AuthFrame({super.key, required this.children, this.maxWidth = 440});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.7), radius: 1.3, colors: [Color(0xFF{= colors.glow =}), Palette.ink]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark(size: 56)),
                    const SizedBox(height: 14),
                    Text(
                      '{= display_name =}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '{= tagline =}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Palette.raised.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Palette.hairlineStrong),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 16))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
