import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'page.dart';
import 'theme.dart';

/// Ponto de corte entre layout de celular (barra inferior) e de computador (rail lateral).
const kDesktopBreakpoint = 800.0;

bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;

class ResponsiveScaffold extends StatelessWidget {
  final Widget child;
  const ResponsiveScaffold({super.key, required this.child});

  static const _destinations = [
{% for e in entities %}    (path: '{= e.route =}', icon: Icons.{= e.icon =}, selected: Icons.{= e.icon =}, label: '{= e.label_plural =}', short: '{= e.label_plural =}'),
{% endfor %}    (path: '/conta', icon: Icons.account_circle_outlined, selected: Icons.account_circle, label: 'Conta', short: 'Conta'),
  ];

  /// O destino da rota atual; a raiz só vale quando nenhum outro casa.
  static int _index(String path) {
    final i = _destinations.lastIndexWhere((d) => d.path != '/' && path.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final idx = _index(path);
    void go(int i) => context.go(_destinations[i].path);
    // Laterais: com o celular deitado, a barra de navegação do Android e o recorte da câmera ficam
    // de um lado; em tela cheia a barra some e o recuo some junto (o SafeArea segue o sistema). Em
    // cima, cada página cuida (a barra dela pinta por baixo da barra de status).
    if (isDesktop(context)) {
      return Scaffold(
        body: Row(
          children: [
            _Rail(index: idx, onSelect: go),
            Expanded(child: SafeArea(left: false, top: false, bottom: false, child: child)),
          ],
        ),
      );
    }
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return Scaffold(
      body: SafeArea(top: false, bottom: false, child: child),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Palette.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: go,
          labelBehavior: narrow ? NavigationDestinationLabelBehavior.onlyShowSelected : null,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: narrow ? d.short : d.label, tooltip: d.label),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _Rail({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // celular deitado passa de 800 de largura mas tem pouca altura: rail sem rótulos e rolável
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.bar,
        border: Border(right: BorderSide(color: Palette.hairline)),
      ),
      child: SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, cons) {
            final short = cons.maxHeight < 560;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: cons.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: onSelect,
                    labelType: short ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: EdgeInsets.only(top: short ? 4 : 10, bottom: short ? 4 : 14),
                      child: BrandMark(size: short ? 32 : 40),
                    ),
                    destinations: [
                      for (final d in ResponsiveScaffold._destinations)
                        NavigationRailDestination(
                          icon: Tooltip(message: d.label, child: Icon(d.icon)),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
