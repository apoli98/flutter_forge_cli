import 'dart:io';

import 'package:flutter_forge_cli/src/cli/runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
