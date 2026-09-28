/// Contas, espelhando `server/src/auth.rs`.
library;

class User {
  final String id, email, name;
  User({required this.id, required this.email, required this.name});
  User.fromJson(Map<String, dynamic> j) : id = j['id'], email = j['email'], name = j['name'] ?? '';

  /// Nome se tiver, senão o email.
  String get display => name.isEmpty ? email : name;
}

class Tokens {
  final String access, refresh;
  final User user;
  Tokens.fromJson(Map<String, dynamic> j) : access = j['access_token'], refresh = j['refresh_token'], user = User.fromJson(j['user']);
}

class Me {
  final User user;
  Me.fromJson(Map<String, dynamic> j) : user = User.fromJson(j['user']);
}
