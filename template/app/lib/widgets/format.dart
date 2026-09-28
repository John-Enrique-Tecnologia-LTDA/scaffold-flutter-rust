/// Textos e números como a tela mostra: plural, milhar com ponto e datas curtas.
library;

/// `plural(3, 'item', 'itens')` → "3 itens"; o plural irregular vai no terceiro argumento.
String plural(int n, String one, [String? many]) => '${fmtInt(n)} ${n == 1 ? one : many ?? '${one}s'}';

/// Inteiro com ponto no milhar: 1025 → "1.025".
String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Dia e mês: "07/10".
String shortDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

/// "agora", "há 5 min", "há 3 h" ou o dia.
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'agora';
  if (d.inHours < 1) return 'há ${d.inMinutes} min';
  if (d.inDays < 1) return 'há ${d.inHours} h';
  return shortDate(t);
}

/// Frase a partir da mensagem crua da API ("nome obrigatório" → "Nome obrigatório.").
String sentence(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  final cap = '${t[0].toUpperCase()}${t.substring(1)}';
  return RegExp(r'[.!?]$').hasMatch(cap) ? cap : '$cap.';
}
