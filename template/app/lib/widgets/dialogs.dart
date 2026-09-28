import 'package:flutter/material.dart';

/// Diálogos do app todo. Cada um que tem campo de texto é dono do controlador: descartá-lo de
/// fora, logo depois do `pop`, quebra a animação de saída que ainda desenha o campo.

/// Pede confirmação. `destructive` pinta o botão de vermelho (apagar, tirar, sair).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirmar',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        scrollable: true,
        title: Text(title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return ok == true;
}

Future<bool> confirmDelete(BuildContext context, {required String title, required String content}) =>
    confirmAction(context, title: title, message: content, action: 'Apagar', destructive: true);

/// Pede um texto. Devolve o texto aparado, `''` se a pessoa apagou (com `clearLabel`), ou null
/// se cancelou.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String label = '',
  String? hint,
  String initial = '',
  String action = 'OK',
  int? maxLength,
  int maxLines = 1,
  String? clearLabel,
  TextInputType? keyboardType,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    label: label,
    hint: hint,
    initial: initial,
    action: action,
    maxLength: maxLength,
    maxLines: maxLines,
    clearLabel: initial.isEmpty ? null : clearLabel,
    keyboardType: keyboardType,
  ),
);

class _TextDialog extends StatefulWidget {
  final String title, label, initial, action;
  final String? hint, clearLabel;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
    required this.maxLines,
    this.hint,
    this.clearLabel,
    this.maxLength,
    this.keyboardType,
  });
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _ctl = TextEditingController(text: widget.initial)..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _ctl.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _ctl,
        autofocus: true,
        maxLength: widget.maxLength,
        minLines: widget.maxLines > 1 ? 3 : 1,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(labelText: widget.label.isEmpty ? null : widget.label, hintText: widget.hint, counterText: ''),
        onSubmitted: widget.maxLines == 1 ? (_) => _done() : null,
      ),
    ),
    actions: [
      if (widget.clearLabel != null) TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(widget.clearLabel!)),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _done, child: Text(widget.action)),
    ],
  );
}
