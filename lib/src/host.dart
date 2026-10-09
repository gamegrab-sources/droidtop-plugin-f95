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
/// (`net.http`, `web.session`, `data`, `notify`). An interface so the
/// plugin's logic is tested without an engine.
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

/// A host call droidtop refused or that failed.
class HostError implements Exception {
  HostError(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// An HTTP answer through droidtop's broker.
class HttpAnswer {
  HttpAnswer(this.status, this.url, this.body);
  final int status;
  final String url;
  final String body;
}

/// The host calls the plugin uses, as plain Dart. It runs contained
/// (docs/plugin-api.md 5.3): no sockets and no files of its own, so every
/// request goes through `net.http` or `web.session fetch` and every byte it
/// keeps through the `data` API.
class Services {
  Services(this.host);
  final Host host;

  Future<Map<String, dynamic>> _data(String api, String op, Map<String, dynamic> args) async {
    final reply = await host.call(api, 1, op, args);
    if (reply['ok'] != true) {
      final error = (reply['error'] as Map?) ?? const {};
      throw HostError(error['code']?.toString() ?? 'FAILED', error['message']?.toString() ?? '$api $op failed');
    }
    return ((reply['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  /// One GET (or [method]) request; [session] sends it with the person's
  /// F95zone session, which droidtop adds itself (`web.session fetch`).
  Future<HttpAnswer> http(String url,
      {String method = 'GET', Map<String, String>? headers, String? body, bool session = false, int timeoutMs = 30000}) async {
    final data = await _data(session ? 'web.session' : 'net', session ? 'fetch' : 'http', {
      'url': url,
      'method': method,
      'headers': ?headers,
      'body': ?body,
      'as': 'text',
      'timeoutMs': timeoutMs,
    });
    return HttpAnswer((data['status'] as num?)?.toInt() ?? 0, data['url']?.toString() ?? url, data['body']?.toString() ?? '');
  }

  /// The plugin's own file [name] as JSON, or null when there is none.
  Future<Object?> readJson(String name) async {
    try {
      final bytes = <int>[];
      while (true) {
        final data = await _data('data', 'read', {'name': name, 'offset': bytes.length, 'length': _chunk, 'as': 'base64'});
        final chunk = base64Decode(data['base64']?.toString() ?? '');
        bytes.addAll(chunk);
        if (data['eof'] == true || chunk.isEmpty) break;
      }
      if (bytes.isEmpty) return null;
      return jsonDecode(utf8.decode(bytes));
    } on HostError {
      // No such file yet (or unreadable): the plugin starts from nothing, as on its first run.
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Writes [value] as JSON to the plugin's own file [name], in chunks the data API takes.
  Future<void> writeJson(String name, Object? value) async {
    final bytes = utf8.encode(jsonEncode(value));
    var offset = 0;
    var first = true;
    do {
      final end = (offset + _chunk) < bytes.length ? offset + _chunk : bytes.length;
      await _data('data', 'write', {
        'name': name,
        'base64': base64Encode(bytes.sublist(offset, end)),
        'append': !first,
      });
      first = false;
      offset = end;
    } while (offset < bytes.length);
  }

  Future<void> notify(String title, String text) async {
    try {
      await _data('notify', 'post', {'title': title, 'text': text});
    } on HostError {
      // A notification the person turned off, or the hourly limit: the update is still on the game's page.
    }
  }

  Future<bool> signedIn() async => (await _data('web.session', 'status', {}))['signedIn'] == true;

  Future<bool> signIn(String url, {String? doneCookie}) async =>
      (await _data('web.session', 'sign_in', {'url': url, 'doneCookie': ?doneCookie}))['signedIn'] == true;

  Future<void> signOut() => _data('web.session', 'clear', {});

  /// Opens [url] in droidtop's web view with the session; the download the page starts, or null.
  Future<Map<String, dynamic>?> openInSession(String url) async {
    final data = await _data('web.session', 'open_in_session', {'url': url});
    if (data['captured'] != true) return null;
    return (data['download'] as Map?)?.cast<String, dynamic>();
  }

  static const int _chunk = 120 * 1024;
}
