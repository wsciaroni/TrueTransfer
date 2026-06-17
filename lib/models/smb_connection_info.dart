class SmbConnectionInfo {
  final String host;
  final String share;
  final String? username;
  final String? password;
  final String? domain;

  SmbConnectionInfo({
    required this.host,
    required this.share,
    this.username,
    this.password,
    this.domain,
  });

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'share': share,
      'username': username,
      'password': password,
      'domain': domain,
    };
  }

  factory SmbConnectionInfo.fromJson(Map<String, dynamic> json) {
    return SmbConnectionInfo(
      host: json['host'] as String,
      share: json['share'] as String,
      username: json['username'] as String?,
      password: json['password'] as String?,
      domain: json['domain'] as String?,
    );
  }
}
