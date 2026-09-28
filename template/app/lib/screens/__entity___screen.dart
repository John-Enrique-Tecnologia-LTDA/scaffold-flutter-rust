import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/{= e.name =}.dart';
import '../widgets/api_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/page.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/theme.dart';

/// {= e.label_plural =} da conta: uma grade que se ajusta à largura (uma coluna no celular, várias
/// no computador), criar, editar e apagar. O formulário abre em diálogo no computador e numa
/// folha de baixo no celular.
class {= e.class_plural =}Screen extends StatefulWidget {
  const {= e.class_plural =}Screen({super.key});
  @override
  State<{= e.class_plural =}Screen> createState() => _{= e.class_plural =}ScreenState();
}

class _{= e.class_plural =}ScreenState extends State<{= e.class_plural =}Screen> with ApiState {
  final _api = ApiClient.instance;
  List<{= e.class =}>? _items;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<void> reload() => fetch(_api.{= e.camel_plural =}(), (v) => _items = v);

  /// Abre o formulário (vazio, ou com o registro para editar) e recarrega se salvou.
  Future<void> _edit([{= e.class =}? item]) async {
    final form = _{= e.class =}Form(item: item);
    final saved = isDesktop(context)
        ? await showDialog<bool>(context: context, builder: (_) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: form)))
        : await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => form);
    if (saved == true) await reload();
  }

  Future<void> _delete({= e.class =} item) async {
    if (!await confirmDelete(context, title: 'Apagar "${item.{= e.title.camel =}}"?', content: 'Some para sempre.')) return;
    await run(() => _api.delete{= e.class =}(item.id), done: '{= e.deleted_label =}');
  }

  @override
  Widget build(BuildContext context) {
    final list = _items;
    return PageScaffold(
      icon: Icons.{= e.icon =},
      title: '{= e.label_plural =}',
      subtitle: list == null ? null : plural(list.length, '{= e.label_lower =}', '{= e.label_plural_lower =}'),
      primary: (icon: Icons.add, label: '{= e.new_label =}', onPressed: busy ? null : () => _edit()),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          notices(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0)),
          Expanded(child: _body(list)),
        ],
      ),
    );
  }

  Widget _body(List<{= e.class =}>? list) {
    if (list == null) return error != null ? ErrorState(error: error!, onRetry: reload) : const LoadingState();
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.{= e.icon =},
        title: '{= e.none_label =}',
        action: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('{= e.new_label =}')),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360, mainAxisExtent: 116, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: list.length,
        itemBuilder: (_, i) => _Card(item: list[i], color: trackColorAt(i), onOpen: () => _edit(list[i]), onDelete: () => _delete(list[i])),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final {= e.class =} item;
  final Color color;
  final VoidCallback onOpen, onDelete;
  const _Card({required this.item, required this.color, required this.onOpen, required this.onDelete});

  /// Os outros campos numa linha de resumo.
  String get _summary => [
{% for f in e.fields if not f.is_title %}
{% if f.kind == "bool" %}
    if (item.{= f.camel =}) '{= f.label =}',
{% elif f.kind in ["string", "text"] %}
    if (item.{= f.camel =}.isNotEmpty) item.{= f.camel =},
{% else %}
    '{= f.label =}: ${item.{= f.camel =}}',
{% endif %}
{% endfor %}
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SectionIcon(Icons.{= e.icon =}, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.{= e.title.camel =}, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(tooltip: 'Apagar', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
                ],
              ),
              const Spacer(),
              Text(_summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              Text('Atualizado ${timeAgo(item.updatedAt)}', style: muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Criar ou editar: fecha com `true` quando o servidor aceitou; o erro dele aparece aqui dentro.
class _{= e.class =}Form extends StatefulWidget {
  final {= e.class =}? item;
  const _{= e.class =}Form({this.item});
  @override
  State<_{= e.class =}Form> createState() => _{= e.class =}FormState();
}

class _{= e.class =}FormState extends State<_{= e.class =}Form> {
{% for f in e.fields %}
{% if f.kind == "bool" %}
  late bool _{= f.camel =} = widget.item?.{= f.camel =} ?? {= f.default_dart =};
{% elif f.kind in ["string", "text"] %}
  late final _{= f.camel =} = TextEditingController(text: widget.item?.{= f.camel =} ?? {= f.default_dart =});
{% else %}
  late final _{= f.camel =} = TextEditingController(text: '${widget.item?.{= f.camel =} ?? {= f.default_dart =}}');
{% endif %}
{% endfor %}
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
{% for f in e.fields if f.kind != "bool" %}
    _{= f.camel =}.dispose();
{% endfor %}
    super.dispose();
  }

  /// O corpo do pedido; número que não se lê vira erro antes de ir ao servidor.
  Map<String, dynamic>? _body() {
{% for f in e.fields %}
{% if f.kind == "int" %}
    final {= f.camel =} = int.tryParse(_{= f.camel =}.text.trim());
    if ({= f.camel =} == null) return _fail('{= f.label =}: digite um número inteiro.');
{% elif f.kind == "float" %}
    final {= f.camel =} = double.tryParse(_{= f.camel =}.text.trim().replaceAll(',', '.'));
    if ({= f.camel =} == null) return _fail('{= f.label =}: digite um número.');
{% endif %}
{% endfor %}
    return {
{% for f in e.fields %}
{% if f.kind in ["string", "text"] %}
      '{= f.name =}': _{= f.camel =}.text.trim(),
{% elif f.kind == "bool" %}
      '{= f.name =}': _{= f.camel =},
{% else %}
      '{= f.name =}': {= f.camel =},
{% endif %}
{% endfor %}
    };
  }

  Map<String, dynamic>? _fail(String message) {
    setState(() => _error = message);
    return null;
  }

  Future<void> _save() async {
    final body = _body();
    if (body == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item = widget.item;
      if (item == null) {
        await ApiClient.instance.create{= e.class =}(body);
      } else {
        await ApiClient.instance.patch{= e.class =}(item.id, body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.item == null ? '{= e.new_label =}' : 'Editar', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
{% for f in e.fields %}
{% if f.kind == "bool" %}
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('{= f.label =}'), value: _{= f.camel =}, onChanged: _busy ? null : (v) => setState(() => _{= f.camel =} = v)),
{% else %}
          TextField(
            controller: _{= f.camel =},
            enabled: !_busy,
{% if loop.first %}
            autofocus: true,
{% endif %}
{% if f.kind == "text" %}
            minLines: 3,
            maxLines: 8,
{% endif %}
{% if f.kind == "int" %}
            keyboardType: TextInputType.number,
{% elif f.kind == "float" %}
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
{% endif %}
{% if f.max is not none and f.kind in ["string", "text"] %}
            maxLength: {= f.max =},
{% endif %}
            decoration: const InputDecoration(labelText: '{= f.label =}', counterText: ''),
          ),
{% endif %}
          const SizedBox(height: 12),
{% endfor %}
          if (_error != null) ...[InlineNotice(_error!), const SizedBox(height: 12)],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _busy ? null : _save, icon: _busy ? const ButtonSpinner() : const Icon(Icons.check), label: const Text('Salvar')),
            ],
          ),
        ],
      ),
    );
  }
}
