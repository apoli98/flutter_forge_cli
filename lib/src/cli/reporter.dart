import 'dart:convert';

final class CliReporter {
  CliReporter(this.out, this.err);

  final StringSink out;
  final StringSink err;
  bool json = false;
  String? command;
  final data = <String, Object?>{};

  void info(String message) {
    if (!json) out.writeln(message);
  }

  void diagnostic(String message) {
    if (!json) err.writeln(message);
  }

  int finish({int exitCode = 0, String? kind, String? message}) {
    if (json) {
      out.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'success': exitCode == 0,
          'exitCode': exitCode,
          'command': command,
          'data': data,
          'error': kind == null ? null : {'kind': kind, 'message': message},
        }),
      );
    }
    return exitCode;
  }
}
