import 'package:flutter/material.dart';

import 'feedback.dart';

/// Estado de tela que conversa com a API: carrega, roda as ações do usuário e mostra o erro ou
/// o aviso inline. Antes cada tela tinha o seu `_load`/`_run`/`_act` com o mesmo try/catch.
mixin ApiState<W extends StatefulWidget> on State<W> {
  String? error, info;
  bool busy = false;

  /// Recarrega o que a tela mostra; `run` chama depois de cada ação que deu certo.
  Future<void> reload();

  /// Busca e aplica o resultado. Na falha guarda o erro legível e devolve false.
  Future<bool> fetch<T>(Future<T> request, void Function(T value) apply) async {
    try {
      final v = await request;
      if (mounted) {
        setState(() {
          apply(v);
          error = null;
        });
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => error = describeError(e));
      return false;
    }
  }

  /// Roda uma ação: marca ocupado, mostra o erro ou o aviso `done` e recarrega a tela.
  Future<bool> run(Future<void> Function() action, {String? done, bool reloadAfter = true}) async {
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await action();
      if (!mounted) return true;
      setState(() => info = done);
      if (reloadAfter) await reload();
      return true;
    } catch (e) {
      if (mounted) setState(() => error = describeError(e));
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Mostra um erro que não veio de chamada nenhuma (validação na própria tela).
  void fail(String message) => setState(() {
    error = message;
    info = null;
  });

  /// Os avisos da tela, prontos para pôr no topo do conteúdo.
  Widget notices({EdgeInsets padding = EdgeInsets.zero}) =>
      NoticeStack(error: error, info: info, padding: padding, onClearError: () => setState(() => error = null), onClearInfo: () => setState(() => info = null));
}
