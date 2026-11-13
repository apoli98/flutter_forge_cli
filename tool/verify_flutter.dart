import 'dart:io';

import 'package:path/path.dart' as p;

/// Exercises the compiled CLI and the exact instructions printed for features.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || !Directory(arguments.single).existsSync()) {
    stderr.writeln(
      'Usage: dart run tool/verify_flutter.dart <existing-temp-parent>',
    );
    exitCode = 64;
    return;
  }
  final repo = Directory.current.path;
  final work = Directory(arguments.single).createTempSync('forge_verify_');
  stdout.writeln('Verification artifacts: ${work.path}');
  final executable = p.join(
    work.path,
    Platform.isWindows ? 'flutter-forge.exe' : 'flutter-forge',
  );
  final app = p.join(work.path, 'verified_app');
  try {
    await run('dart', [
      'compile',
      'exe',
      'bin/flutter_forge.dart',
      '-o',
      executable,
    ], repo);
    await run(executable, ['--help'], work.path);
    await run(executable, ['--version'], work.path);
    await run(executable, [
      'create',
      'dry_app',
      '--platforms',
      'web',
      '--dry-run',
    ], work.path);
    if (Directory(p.join(work.path, 'dry_app')).existsSync()) {
      throw StateError('Compiled create dry-run wrote a target');
    }
    await run(executable, [
      'create',
      'verified_app',
      '--platforms',
      'web',
    ], work.path);
    await run('flutter', ['analyze'], app);
    await run('flutter', ['test'], app);
    final snippets = <({String imports, String route})>[];
    for (final feature in ['order_history', 'activity']) {
      final style = feature == 'activity' ? 'bloc' : 'cubit';
      final result = await run(executable, [
        'feature',
        feature,
        '--state',
        style,
        '--project-dir',
        app,
      ], work.path);
      final imports = RegExp(
        r"^import .+;$",
        multiLine: true,
      ).allMatches(result).map((m) => m[0]!).join('\n');
      final route = RegExp(
        r'^\w+Route\(create\w+: \w+\.new\),$',
        multiLine: true,
      ).firstMatch(result)?[0];
      if (imports.split('\n').length != 2 || route == null) {
        throw StateError(
          'Could not extract exact wiring instructions for $feature',
        );
      }
      snippets.add((imports: imports, route: route));
    }
    // Only this disposable app is edited. The CLI never patches the router.
    final router = File(p.join(app, 'lib/app/router.dart'));
    var source = router.readAsStringSync();
    for (final snippet in snippets) {
      source = '${snippet.imports}\n$source';
      source = source.replaceFirst(
        'routes: [',
        'routes: [\n    ${snippet.route}',
      );
    }
    router.writeAsStringSync(source);
    File(p.join(app, 'test/registered_routes_test.dart')).writeAsStringSync(
      '''import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verified_app/app/router.dart';

void main() {
  for (final path in ['/order_history', '/activity']) {
    testWidgets('registered route \$path works through the app router', (tester) async {
      final router = createRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Count: 0'), findsOneWidget);
      await tester.tap(find.byTooltip('Increment'));
      await tester.pumpAndSettle();
      expect(find.text('Count: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    });
  }
}
''',
    );
    await run('dart', ['format', 'lib', 'test'], app);
    await run('flutter', ['analyze'], app);
    await run('flutter', ['test'], app);
    await run('flutter', ['build', 'web'], app);
    stdout.writeln(
      'PASS: compiled CLI, new app, both feature variants, exact route snippets, and web build.',
    );
  } on Exception catch (e) {
    stderr.writeln('VERIFICATION FAILED: $e');
    exitCode = 1;
  }
  stdout.writeln('Artifacts retained at ${work.path}');
}

Future<String> run(String executable, List<String> args, String cwd) async {
  stdout.writeln('\n> $executable ${args.join(' ')}\n  in $cwd');
  final result = await Process.run(
    executable,
    args,
    workingDirectory: cwd,
    runInShell: Platform.isWindows,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      'Verification command failed',
      result.exitCode,
    );
  }
  return result.stdout as String;
}
