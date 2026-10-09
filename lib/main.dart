// The F95zone source for droidtop, a flutter_embed plugin (droidtop
// docs/plugin-api.md 1.3 and 3 A6). It draws nothing: droidtop hosts this
// engine headless and talks to it over one MethodChannel, JSON in and JSON
// out, and every row, sheet and search result is droidtop's own UI.
//
// It is written to run contained (docs/plugin-api.md 5.3): no sockets, no
// files of its own, so the network goes through droidtop's `net.http` host
// call and state through droidtop's data API and vault, never through
// package-level storage.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/host.dart';
import 'src/plugin.dart';

/// The plugin id, stamped by droidtop_plugin/build.sh; the channel name
/// must equal it, because droidtop builds the channel from the installed id.
const String pluginId = String.fromEnvironment('DROIDTOP_PLUGIN_ID', defaultValue: 'bi0shacker001.f95');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final channel = MethodChannel('dev.droidtop.pluginhost/$pluginId');
  final plugin = F95Plugin(ChannelHost(channel));
  channel.setMethodCallHandler((call) async {
    if (call.method == 'handle') {
      final envelope = jsonDecode(call.arguments as String) as Map<String, dynamic>;
      return jsonEncode(await plugin.handle(envelope));
    }
    return jsonEncode(Reply.error('UNSUPPORTED', 'unknown method ${call.method}'));
  });
  // The flutter_embed readiness handshake: droidtop's onLoad waits for it,
  // and a call sent before it would find no handler.
  channel.invokeMethod('ready');
}
