import 'dart:io';

import 'package:flutter_forge_cli/src/project/names.dart';
import 'package:flutter_forge_cli/src/project/project_config.dart';
import 'package:flutter_forge_cli/src/toolchain/flutter_toolchain.dart';
import 'package:path/path.dart' as p;

Directory temporaryDirectory() {
  final base = Directory(
    p.join(Directory.current.path, '.dart_tool', 'test_tmp'),
  )..createSync(recursive: true);
  return base.createTempSync('forge_');
}

void writeFile(String root, String path, String contents) {
  final file = File(p.join(root, path));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void writeProject(String root) {
  writeFile(
    root,
    configFileName,
    ProjectConfig(DartName.parse('demo')).encode(),
  );
  writeFile(root, 'pubspec.yaml', '''name: demo
dependencies:
  flutter:
    sdk: flutter
  flutter_bloc: ^9.1.1
  go_router: ^18.1.4
  material_ui: ^1.11.0
dev_dependencies:
  bloc_test: ^10.0.0
''');
}

Map<String, String> snapshot(String root) => {
  for (final entity in Directory(
    root,
  ).listSync(recursive: true, followLinks: false))
    if (entity is File)
      p.relative(entity.path, from: root): entity.readAsStringSync(),
};

final class FakeToolchain implements FlutterToolchain {
  final calls = <({List<String> args, String cwd})>[];
  int? failAt;
  bool failBeforeOutput = false;
  bool unexpectedCollision = false;

  @override
  Future<void> run(
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    calls.add((args: List.of(arguments), cwd: workingDirectory));
    if (failBeforeOutput) {
      throw ProcessException('flutter', arguments, 'not found');
    }
    if (arguments.first == 'create') {
      final target = arguments.last;
      writeFile(target, 'lib/main.dart', 'stock main');
      writeFile(target, 'pubspec.yaml', 'stock pubspec');
      writeFile(target, 'test/widget_test.dart', 'stock test');
      writeFile(target, 'web/index.html', 'platform scaffold');
      if (unexpectedCollision) {
        writeFile(target, 'lib/app/router.dart', 'unexpected content');
      }
    }
    if (calls.length == failAt) {
      throw ProcessException('flutter', arguments, 'simulated failure', 7);
    }
  }
}
