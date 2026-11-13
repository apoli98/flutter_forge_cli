import 'dart:io';

import 'package:path/path.dart' as p;

abstract interface class FlutterToolchain {
  Future<void> run(List<String> arguments, {required String workingDirectory});
}

final class SystemFlutterToolchain implements FlutterToolchain {
  SystemFlutterToolchain({required this.output});

  final StringSink output;

  @override
  Future<void> run(
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final executable = _findFlutter();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.normal,
    );
    final stdoutDone = process.stdout
        .transform(systemEncoding.decoder)
        .forEach(output.write);
    final stderrDone = process.stderr
        .transform(systemEncoding.decoder)
        .forEach(output.write);
    final code = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (code != 0) {
      throw ProcessException(
        executable,
        arguments,
        'Flutter command failed',
        code,
      );
    }
  }

  String _findFlutter() {
    final path = Platform.environment['PATH'] ?? '';
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      final executable = p.join(
        directory,
        Platform.isWindows ? 'flutter.bat' : 'flutter',
      );
      if (File(executable).existsSync()) return p.absolute(executable);
    }
    throw const ProcessException(
      'flutter',
      [],
      'Flutter was not found on PATH. Install Flutter or activate your FVM environment.',
    );
  }
}
