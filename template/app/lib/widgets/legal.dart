import 'package:flutter/material.dart';

import '../api/client.dart';
import '../platform/platform.dart';

/// A política de privacidade e os termos (páginas estáticas em app/web), abertos fora do app.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final base = ApiClient.instance.base;
    Widget link(String label, String path) => TextButton(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
      onPressed: () => openExternal('$base$path'),
      child: Text(label),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link('Política de privacidade', '/privacidade'),
        Text('·', style: muted),
        link('Termos de uso', '/termos'),
      ],
    );
  }
}
