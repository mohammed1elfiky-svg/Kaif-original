import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Calls of the lsFusion server API: POST `{server}/exec/Distribution.<action>`,
/// authenticated as the distributor's user (basic authentication).
class Api {
  final String server, user, password;
  final http.Client client;

  Api(this.server, this.user, this.password, {http.Client? client}) : client = client ?? http.Client();

  Uri _uri(String action) {
    final base = server.endsWith('/') ? server.substring(0, server.length - 1) : server;
    return Uri.parse('$base/exec/Distribution.$action');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Basic ${base64.encode(utf8.encode('$user:$password'))}',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<dynamic> _post(String action, [Object? body]) async {
    final http.Response r;
    try {
      r = await client
          .post(_uri(action), headers: _headers, body: body == null ? null : jsonEncode(body))
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ApiException('تعذر الاتصال بالخادم: $e');
    }
    final text = utf8.decode(r.bodyBytes);
    if (r.statusCode == 401) throw ApiException('اسم المستخدم أو كلمة المرور غير صحيحة');
    if (r.statusCode != 200) throw ApiException('خطأ من الخادم (${r.statusCode}): $text');
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<Map<String, dynamic>> getData() async => (await _post('getData')) as Map<String, dynamic>;

  /// Returns the result for each document id: "ok" or an error message.
  Future<Map<String, String>> upload(List<Map<String, dynamic>> invoices, List<Map<String, dynamic>> payments) async {
    final res = await _post('upload', {'invoices': invoices, 'payments': payments});
    final list = res is List ? res : const [];
    return {for (final e in list.cast<Map<String, dynamic>>()) e['id'].toString(): e['result'].toString()};
  }
}
