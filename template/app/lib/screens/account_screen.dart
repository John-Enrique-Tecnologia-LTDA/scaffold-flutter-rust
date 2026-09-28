import 'package:flutter/material.dart';

import '../api/client.dart';
import '../auth/session.dart';
import '../widgets/api_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/legal.dart';
import '../widgets/page.dart';

/// A conta: nome, sair deste aparelho ou de todos, e apagar a conta.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with ApiState {
  final _session = Session.instance;
  final _api = ApiClient.instance;

  @override
  Future<void> reload() => _session.refreshMe();

  Future<void> _rename() async {
    final name = await promptText(context, title: 'Seu nome', label: 'Nome', initial: _session.user?.name ?? '', action: 'Salvar', maxLength: 80);
    if (name == null) return;
    await run(() => _api.patchMe(name: name), done: 'Nome salvo.');
  }

  Future<void> _logoutAll() async {
    if (!await confirmAction(
      context,
      title: 'Sair de todos os aparelhos?',
      message: 'Todas as sessões desta conta são encerradas, inclusive esta.',
      action: 'Sair de todos',
      destructive: true,
    )) {
      return;
    }
    await run(() async {
      await _api.logoutAll();
      await _session.signOut(notifyServer: false);
    }, reloadAfter: false);
  }

  Future<void> _delete() async {
    if (!await confirmAction(
      context,
      title: 'Apagar a conta?',
      message: 'A conta e tudo o que é dela some para sempre. Não tem volta.',
      action: 'Apagar a conta',
      destructive: true,
    )) {
      return;
    }
    await run(() async {
      await _api.deleteAccount();
      await _session.signOut(notifyServer: false);
    }, reloadAfter: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = _session.user;
    return PageScaffold(
      icon: Icons.account_circle_outlined,
      title: 'Conta',
      subtitle: u?.email,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  notices(padding: const EdgeInsets.only(bottom: 12)),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: Text(u?.name.isNotEmpty == true ? u!.name : 'Sem nome'),
                          subtitle: const Text('Nome'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: busy ? null : _rename,
                        ),
                        const Divider(),
                        ListTile(leading: const Icon(Icons.alternate_email), title: Text(u?.email ?? ''), subtitle: const Text('Email')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        ListTile(leading: const Icon(Icons.logout), title: const Text('Sair'), onTap: busy ? null : () => _session.signOut()),
                        const Divider(),
                        ListTile(leading: const Icon(Icons.devices_other), title: const Text('Sair de todos os aparelhos'), onTap: busy ? null : _logoutAll),
                        const Divider(),
                        ListTile(
                          leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                          title: Text('Apagar a conta', style: TextStyle(color: theme.colorScheme.error)),
                          onTap: busy ? null : _delete,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LegalLinks(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
