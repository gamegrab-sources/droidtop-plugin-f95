// The F95zone source for droidtop, a flutter_embed plugin (droidtop
// docs/plugin-api.md 1.3 and 3 A2, A3, A6). It draws nothing: droidtop hosts
// this engine headless and talks to it over one MethodChannel, JSON in and
// JSON out, and every row, sheet and search result is droidtop's own UI. The
// only page a person sees that is not droidtop's list UI is F95zone's own,
// in droidtop's web view, for sign-in and downloads.
//
// It is written to run contained (docs/plugin-api.md 5.3): no sockets, no
// files of its own, so the network goes through droidtop's `net.http` and
// `web.session`, and state through droidtop's data API, never through
// package-level storage.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/host.dart';
import 'src/plugin.dart';

/// The plugin id, stamped by droidtop_plugin/build.sh; the channel name
/// must equal it, because droidtop builds the channel from the installed id.
const String pluginId = String.fromEnvironment('DROIDTOP_PLUGIN_ID', defaultValue: 'gamegrab.f95');

late final MethodChannel _channel;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _channel = MethodChannel('dev.droidtop.pluginhost/$pluginId');
  final plugin = F95Plugin(ChannelHost(_channel));
  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'handle':
        final envelope = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        return jsonEncode(await plugin.handle(envelope));
      case 'startJob':
        // A contract 2 job: `startJob(jobId, capability, {call: <envelope>})`; the
        // answer goes back over jobComplete, not this method's return value.
        final payload = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        final jobId = payload['jobId'] as String;
        final raw = (payload['args'] as Map?)?['call'];
        unawaited(_runJob(plugin, jobId, raw is String ? jsonDecode(raw) as Map<String, dynamic> : null));
        return jsonEncode({'ok': true});
      case 'cancelJob':
        // Every job here is one request at a time and ends on its own; nothing to stop mid-way.
        return jsonEncode({'ok': true});
    }
    return jsonEncode(Reply.error('UNSUPPORTED', 'unknown method ${call.method}'));
  });
  // The flutter_embed readiness handshake: droidtop's onLoad waits for it,
  // and a call sent before it would find no handler.
  _channel.invokeMethod('ready');
}

Future<void> _runJob(F95Plugin plugin, String jobId, Map<String, dynamic>? envelope) async {
  Map<String, dynamic> result;
  if (envelope == null) {
    result = {'ok': false, 'error': 'Missing job envelope'};
  } else {
    result = await plugin.job(
      envelope['point'] as String? ?? '',
      envelope['op'] as String? ?? '',
      (envelope['args'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
  await _channel.invokeMethod('jobComplete', jsonEncode({'jobId': jobId, 'result': jsonEncode(result)}));
}
