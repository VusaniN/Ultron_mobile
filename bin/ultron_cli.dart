import 'dart:async';
import 'package:ultron_mobile/cli/terminal_handler.dart';

Future<void> main() async {
  final handler = TerminalHandler();
  try {
    await handler.initialize();
    await handler.run();
  } catch (e) {
    print('Fatal error: $e');
  }
}
