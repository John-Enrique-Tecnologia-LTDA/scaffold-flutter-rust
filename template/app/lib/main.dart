import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'auth/session.dart';
import 'platform/platform.dart';
import 'screens/account_screen.dart';
import 'screens/link_screen.dart';
import 'screens/login_screen.dart';
{% for e in entities %}import 'screens/{= e.name =}_screen.dart';
{% endfor %}import 'widgets/responsive_scaffold.dart';
import 'widgets/theme.dart';

Future<void> main() async {
  usePathUrlStrategy();
  GoRouter.optionURLReflectsImperativeAPIs = true;
  WidgetsFlutterBinding.ensureInitialized();
  await initPlatform();
  await Session.instance.load();
  runApp(const {= class_prefix =}App());
}

/// Rotas que abrem sem sessão: o login, o link do email e a volta do app do Discord.
const _public = {'/login', '/entrar', '/authorize/callback'};

final _router = GoRouter(
  refreshListenable: Session.instance,
  // sem sessão vai para o login, lembrando para onde ia
  redirect: (context, state) {
    final path = state.uri.path;
    if (!Session.instance.signedIn) {
      if (_public.contains(path)) return null;
      return path == '/' ? '/login' : Uri(path: '/login', queryParameters: {'from': state.uri.toString()}).toString();
    }
    if (path == '/login') return state.uri.queryParameters['from'] ?? '/';
    if (path == '/authorize/callback') return '/';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, s) => LoginScreen(
        notice: s.extra as String?,
        from: s.uri.queryParameters['from'],
        oauthToken: s.uri.queryParameters['oauth'],
        oauthError: s.uri.queryParameters['erro'],
      ),
    ),
    // a volta do app do Discord no Android (`discord-{id}:/authorize/callback`, auth/social.dart)
    GoRoute(
      path: '/authorize/callback',
      builder: (_, s) =>
          LoginScreen(discordApp: (code: s.uri.queryParameters['code'], state: s.uri.queryParameters['state'], error: s.uri.queryParameters['error'])),
    ),
    GoRoute(
      path: '/entrar',
      builder: (_, s) => LinkScreen(token: s.uri.queryParameters['token']),
    ),
    ShellRoute(
      builder: (context, state, child) => ResponsiveScaffold(child: child),
      routes: [
{% for e in entities %}        GoRoute(path: '{= e.route =}', builder: (_, _) => const {= e.class_plural =}Screen()),
{% endfor %}        GoRoute(path: '/conta', builder: (_, _) => const AccountScreen()),
      ],
    ),
  ],
);

class {= class_prefix =}App extends StatelessWidget {
  const {= class_prefix =}App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(title: '{= display_name =}', debugShowCheckedModeBanner: false, theme: buildTheme(), routerConfig: _router);
}
