import 'dart:convert';

import 'package:flutter/services.dart';

/// A contract 2 reply (droidtop docs/plugin-api.md 1.3): `{ok, data}` or
/// `{ok: false, error: {code, message}}`, with droidtop's closed set of codes.
class Reply {
  static Map<String, dynamic> ok([Map<String, dynamic> data = const {}]) => {'ok': true, 'data': data};

  static Map<String, dynamic> error(String code, String message) => {
        'ok': false,
        'error': {'code': code, 'message': message},
      };
}

/// What the plugin asks of droidtop: a host call through the broker
/// (`net.http`, `vault`, `data`, ...). An interface so the plugin's logic is
/// tested without an engine.
abstract class Host {
  /// Calls [api]@[version] [op] with [args]; the reply envelope as droidtop sent it.
  Future<Map<String, dynamic>> call(String api, int version, String op, Map<String, dynamic> args);
}

/// The real host: the `hostCall` method on the plugin's own channel.
class ChannelHost implements Host {
  ChannelHost(this._channel);
  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>> call(String api, int version, String op, Map<String, dynamic> args) async {
    final raw = await _channel.invokeMethod<String>(
      'hostCall',
      jsonEncode({'api': api, 'version': version, 'op': op, 'args': args}),
    );
    if (raw == null) return Reply.error('FAILED', 'the host returned nothing');
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
