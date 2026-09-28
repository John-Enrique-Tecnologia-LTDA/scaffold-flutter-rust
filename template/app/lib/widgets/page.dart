import 'package:flutter/material.dart';

import 'responsive_scaffold.dart';
import 'theme.dart';

/// Ação principal da página: botão cheio na barra no computador, botão flutuante no celular.
typedef PrimaryAction = ({IconData icon, String label, VoidCallback? onPressed});

/// Esqueleto das páginas do app: ícone da seção, título
/// forte com uma linha de resumo embaixo, e as ações à direita.
class PageScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Ocupa o espaço entre o título e as ações (uma busca, por exemplo).
  final Widget? middle;
  final List<Widget> actions;

  /// Faixa embaixo da barra (abas, busca no celular).
  final PreferredSizeWidget? bottom;
  final PrimaryAction? primary;
  final bool showBack;
  final Widget body;

  const PageScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.subtitle,
    this.middle,
    this.actions = const [],
    this.bottom,
    this.primary,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final p = primary;
    return Scaffold(
      appBar: PageBar(
        icon: icon,
        title: title,
        subtitle: subtitle,
        middle: middle,
        actions: [
          ...actions,
          if (desktop && p != null) ...[
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: p.onPressed, icon: Icon(p.icon, size: 18), label: Text(p.label)),
          ],
        ],
        bottom: bottom,
        showBack: showBack,
      ),
      floatingActionButton: desktop || p == null ? null : FloatingActionButton.extended(onPressed: p.onPressed, icon: Icon(p.icon), label: Text(p.label)),
      body: body,
    );
  }
}

class PageBar extends StatelessWidget implements PreferredSizeWidget {
  static const height = 60.0;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? middle;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final bool showBack;
  const PageBar({super.key, required this.icon, required this.title, this.subtitle, this.middle, this.actions = const [], this.bottom, this.showBack = false});

  @override
  Size get preferredSize => Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final heading = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
    return Material(
      color: Palette.bar,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Palette.hairline)),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: height,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 16),
                  child: Row(
                    children: [
                      if (showBack) const BackButton() else ...[SectionIcon(icon), SizedBox(width: narrow ? 10 : 12)],
                      if (middle == null)
                        Expanded(child: heading)
                      else ...[
                        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: heading),
                        const SizedBox(width: 16),
                        Expanded(child: middle!),
                      ],
                      ...actions,
                    ],
                  ),
                ),
              ),
              ?bottom,
            ],
          ),
        ),
      ),
    );
  }
}

/// O ícone da seção num quadrado com a cor da marca.
class SectionIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const SectionIcon(this.icon, {super.key, this.color, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint.withValues(alpha: 0.26), tint.withValues(alpha: 0.08)]),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, size: size * 0.55, color: tint),
    );
  }
}

/// Marca do {= display_name =}: a inicial num quadrado com o degradê da marca, a mesma peça do login,
/// da navegação e dos ícones (app/web/favicon.svg).
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.28),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF{= colors.accent_light =}), Color(0xFF{= colors.accent_dark =})]),
      boxShadow: [BoxShadow(color: Palette.accent.withValues(alpha: 0.35), blurRadius: size * 0.4, offset: Offset(0, size * 0.08))],
    ),
    child: Text(
      '{= initial =}',
      style: TextStyle(fontSize: size * 0.58, fontWeight: FontWeight.w800, color: const Color(0xFF{= colors.on_accent =}), height: 1),
    ),
  );
}
