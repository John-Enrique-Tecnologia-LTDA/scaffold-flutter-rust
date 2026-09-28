/// {= e.label_plural =}, espelhando `server/src/routes/{= e.plural =}.rs`.
library;

class {= e.class =} {
  final String id;
{% for f in e.fields %}
  final {= f.dart =} {= f.camel =};
{% endfor %}
  final DateTime createdAt, updatedAt;

  {= e.class =}.fromJson(Map<String, dynamic> j)
      : id = j['id'],
{% for f in e.fields %}
        {= f.camel =} = {% if f.kind == "float" %}(j['{= f.name =}'] as num).toDouble(){% else %}j['{= f.name =}']{% endif %},
{% endfor %}
        createdAt = DateTime.parse(j['created_at']),
        updatedAt = DateTime.parse(j['updated_at']);
}
