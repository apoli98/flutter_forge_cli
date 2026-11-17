import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_forge_cli/src/project/app_dependencies.dart';
import 'package:flutter_forge_cli/src/project/names.dart';
import 'package:flutter_forge_cli/src/project/profiles.dart';
import 'package:flutter_forge_cli/src/cli/code_generation.dart';
import 'package:flutter_forge_cli/src/templates/app_templates.dart';

/// Runs the compiled CLI and compiles its exact structured wiring contract.
Future<void> main(List<String> arguments) async {
  final resume = Platform.environment['FORGE_VERIFY_FROM'];
  final selections = {
    for (final profile in LintProfile.values)
      for (final recipe in Recipe.values)
        for (final state in StateStyle.values)
          'verified_${profile.configName}_${recipe.name}_${state.name}',
    'legacy',
  };
  if (arguments.length != 1 ||
      !Directory(arguments.single).existsSync() ||
      (resume != null && !selections.contains(resume))) {
    stderr.writeln(
      'Usage: dart run tool/verify_flutter.dart <existing-temp-parent>\nOptional FORGE_VERIFY_FROM selects a printed matrix app name for a partial run.',
    );
    exitCode = 64;
    return;
  }
  final repo = Directory.current.path;
  final work = Directory(arguments.single).createTempSync('forge_verify_');
  final executable = p.join(work.path, 'flutter-forge');
  stdout.writeln('Verification artifacts: ${work.path}');
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
      'ios,android',
      '--dry-run',
      '--json',
    ], work.path);
    if (Directory(p.join(work.path, 'dry_app')).existsSync()) {
      throw StateError('Dry run wrote a target');
    }
    var started = resume == null;
    for (final profile in LintProfile.values) {
      for (final recipe in Recipe.values) {
        for (final state in StateStyle.values) {
          final name =
              'verified_${profile.configName}_${recipe.name}_${state.name}';
          started = started || name == resume;
          if (!started) continue;
          final app = p.join(work.path, name);
          await run(executable, [
            'create',
            name,
            '--platforms',
            'ios,android',
            '--lint-profile',
            profile.configName,
            '--recipe',
            recipe.name,
            '--state',
            state.name,
            '--json',
          ], work.path);
          await run('flutter', ['analyze'], app);
          await run('flutter', ['test'], app);
          // Business names must coexist with functional-library exports. Analyze
          // and run these real generated sources under each lint profile below.
          for (final feature in [
            'order',
            'either',
            'option',
            'task',
            'provider',
            'notifier',
            'change',
            'stream',
            'api_client',
            'get_it',
            'json_converter',
            'nonempty_string_converter',
          ]) {
            await run(executable, [
              'feature',
              feature,
              '--project-dir',
              app,
              '--json',
              '--no-pub',
            ], work.path);
          }
          // Overrides never install packages themselves. The consuming developer does.
          final override =
              StateStyle.values[(state.index + 1) % StateStyle.values.length];
          final extraDependencies = [
            ...dependenciesFor(recipe, state: override).entries
                .where(
                  (entry) => !dependenciesFor(
                    recipe,
                    state: state,
                  ).containsKey(entry.key),
                )
                .map((entry) => '${entry.key}@${entry.value}'),
            ...devDependenciesFor(profile, state: override).entries
                .where(
                  (entry) => !devDependenciesFor(
                    profile,
                    state: state,
                  ).containsKey(entry.key),
                )
                .map((entry) => 'dev:${entry.key}@${entry.value}'),
          ];
          if (extraDependencies.isNotEmpty) {
            await run('flutter', ['pub', 'add', ...extraDependencies], app);
          }
          final registrations = <Map<String, dynamic>>[];
          for (final style in [state, override]) {
            final feature = 'registered_${style.name}';
            final raw = await run(executable, [
              'feature',
              feature,
              '--state',
              style.name,
              '--route',
              '/account/$feature',
              '--project-dir',
              app,
              '--json',
              '--no-pub',
            ], work.path);
            final result = jsonDecode(raw) as Map<String, dynamic>;
            final data = result['data'] as Map<String, dynamic>;
            final wiring = data['wiring'] as Map<String, dynamic>;
            final imports = (wiring['imports'] as List<dynamic>).cast<String>();
            final text = wiring['text'] as String;
            if (!imports.every(text.contains) ||
                !text.contains(wiring['routeEntry'] as String)) {
              throw StateError('Text and JSON wiring disagree');
            }
            registrations.add(wiring);
          }
          await verifyManagedRoutes(app, name, registrations, recipe);
          await verifyManagedEditRefusal(executable, app, work.path);
          await verifyCodegenRefusal(executable, app, work.path);
          // Consumer-owned composition: use the emitted imports, parameters and
          // constructor expressions verbatim, with explicitly local clean adapters.
          File(
            p.join(app, 'test/registered_routes_test.dart'),
          ).writeAsStringSync('''import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
${registrations.expand((wiring) => (wiring['imports'] as List<dynamic>).cast<String>()).join('\n')}
${recipe == Recipe.clean ? registrations.map((wiring) {
                  final feature = (wiring['location'] as String).split('/').last;
                  return '''import 'package:$name/features/$feature/data/models/${feature}_model.dart';''';
                }).join('\n') : ''}

GoRouter createRouter(${recipe == Recipe.clean ? '{${registrations.map((wiring) => 'required ${wiring['requiredParameter']}').join(',')}}' : ''}) => GoRouter(
  initialLocation: '${registrations.first['location']}',
  routes: [${registrations.map((wiring) => wiring['routeEntry']).join('\n')}],
);

${recipe == Recipe.clean ? registrations.map((wiring) {
                  final feature = (wiring['location'] as String).split('/').last;
                  final c = DartName.parse(feature).className;
                  return '''final class Local${c}Datasource implements ${c}Datasource {
  const new();
  @override
  Future<${c}Model> load() async => const ${c}Model(id: '1', title: '$c content');
}''';
                }).join('\n') : ''}

void main() {
  for (final entry in {${registrations.map((wiring) {
            final feature = (wiring['location'] as String).split('/').last;
            return "'${wiring['location']}': '${recipe == Recipe.clean ? '${DartName.parse(feature).className} content' : 'Count: 0'}'";
          }).join(',')}}.entries) {
    testWidgets('registered route ${r'${entry.key}'} uses the exact constructor wiring', (tester) async {
      final router = createRouter(${recipe == Recipe.clean ? registrations.map((wiring) => '${DartName.parse((wiring['location'] as String).split('/').last).memberName}Datasource: const Local${DartName.parse((wiring['location'] as String).split('/').last).className}Datasource()').join(',') : ''});
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      router.go(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
    });
  }
}
''');
          await run('dart', [
            'fix',
            '--apply',
            '--code=directives_ordering',
          ], app);
          await run('dart', ['format', 'lib', 'test'], app);
          for (final command in generationCommands) {
            await run('flutter', command, app);
          }
          await run('flutter', ['analyze'], app);
          await run('flutter', ['test'], app);
        }
      }
    }
    final counter = p.join(work.path, 'legacy_counter');
    await run(executable, [
      'create',
      'legacy_counter',
      '--recipe',
      'counter',
      '--platforms',
      'ios,android',
      '--json',
    ], work.path);
    // Simulate real schema v1 metadata without rewriting anything via the CLI.
    File(p.join(counter, 'flutter_forge.yaml'))
        .writeAsStringSync('schema_version: 1\npackage: legacy_counter\n');
    await run('flutter', ['pub', 'add', 'dev:flutter_lints@^6.0.0'], counter);
    await run('flutter', [
      'pub',
      'run',
      'tool/fix_localization_imports.dart',
    ], counter);
    await run(executable, [
      'feature',
      'demo',
      '--state',
      'bloc',
      '--route',
      '/legacy/demo',
      '--project-dir',
      counter,
      '--json',
    ], work.path);
    await run('flutter', ['analyze'], counter);
    await run('flutter', ['test'], counter);
    const schema2 =
        'schema_version: 2\npackage: legacy_counter\nrecipe: counter\nlint_profile: very_good\n';
    final metadata = File(p.join(counter, 'flutter_forge.yaml'));
    metadata.writeAsStringSync(schema2);
    final legacyResult = jsonDecode(
      await run(executable, [
        'feature',
        'schema_two',
        '--project-dir',
        counter,
        '--json',
      ], work.path),
    ) as Map<String, dynamic>;
    if ((legacyResult['data'] as Map<String, dynamic>)['state'] != 'cubit' ||
        metadata.readAsStringSync() != schema2) {
      throw StateError('Schema 2 default or metadata preservation failed');
    }
    await run('flutter', ['analyze'], counter);
    await run('flutter', ['test'], counter);
    const schema3 =
        'schema_version: 3\npackage: legacy_counter\nrecipe: counter\nlint_profile: very_good\nstate: provider\n';
    metadata.writeAsStringSync(schema3);
    await run('flutter', ['pub', 'add', 'provider@^6.1.5+1'], counter);
    await run('flutter', [
      'pub',
      'run',
      'tool/fix_localization_imports.dart',
    ], counter);
    final schema3Result = jsonDecode(
      await run(executable, [
        'feature',
        'schema_three',
        '--project-dir',
        counter,
        '--json',
      ], work.path),
    ) as Map<String, dynamic>;
    if ((schema3Result['data'] as Map<String, dynamic>)['state'] !=
            'provider' ||
        metadata.readAsStringSync() != schema3) {
      throw StateError(
        'Schema 3 state default or metadata preservation failed',
      );
    }
    await run('flutter', ['analyze'], counter);
    await run('flutter', ['test'], counter);
    await verifyInit(executable, work.path);
    stdout.writeln(
      '${resume == null ? 'PASS: full 16-app matrix' : 'PASS: partial matrix from $resume'}; compiled CLI; iOS/Android scaffolds; real Freezed/JSON and gen-l10n; managed route/DI navigation and edit refusal; native and cross-backend exact manual route wiring; identifier collisions; legacy schemas; metadata-only init/manual dependency commands. Flutter analyze and test passed for every selected app.',
    );
  } on Exception catch (e) {
    stderr.writeln('VERIFICATION FAILED: $e');
    exitCode = 1;
  }
  stdout.writeln('Artifacts retained at ${work.path}');
}

Future<void> verifyManagedRoutes(
  String app,
  String name,
  List<Map<String, dynamic>> registrations,
  Recipe recipe,
) async {
  final locations = registrations.map((wiring) => wiring['location'] as String);
  File(p.join(app, 'test/managed_routes_test.dart'))
      .writeAsStringSync('''import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:$name/app/dependencies.dart';
import 'package:$name/app/router.dart';
import 'package:$name/core/network/api_client.dart';

void main() {
  testWidgets('automatic route and DI registration navigates without manual wiring', (tester) async {
    final services = createDependencies();
    expect(services<ApiClient>(), same(services<ApiClient>()));
    final router = createRouter(services);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    for (final entry in {${locations.map((location) => "'$location': '${recipe == Recipe.clean ? '${DartName.parse(location.split('/').last).className} local starter' : 'Count: 0'}'").join(',')}}.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await services.reset();
  });
}
''');
}

Future<void> verifyManagedEditRefusal(
  String executable,
  String app,
  String cwd,
) async {
  final router = File(p.join(app, 'lib/app/router.dart'));
  final original = router.readAsStringSync();
  router.writeAsStringSync(
    '$original\n// User-owned edit: automatic registration must stop.\n',
  );
  Map<String, String> snapshot() => {
    for (final dir in ['lib', 'test'])
      for (final file in Directory(
        p.join(app, dir),
      ).listSync(recursive: true).whereType<File>())
        p.relative(file.path, from: app): base64Encode(file.readAsBytesSync()),
    'flutter_forge.yaml': File(p.join(app, 'flutter_forge.yaml'))
        .readAsStringSync(),
  };
  final before = jsonEncode(snapshot());
  final result = await Process.run(executable, [
    'feature',
    'must_refuse',
    '--project-dir',
    app,
    '--json',
  ], workingDirectory: cwd);
  if (result.exitCode != 1 ||
      !'${result.stdout}'.contains('missing or edited') ||
      jsonEncode(snapshot()) != before) {
    throw StateError(
      'Managed edit refusal failed: ${result.stdout} ${result.stderr}',
    );
  }
  router.writeAsStringSync(original);
}

Future<void> verifyCodegenRefusal(
  String executable,
  String app,
  String cwd,
) async {
  final directory = Directory(p.join(app, 'lib/l10n'));
  final saved = p.join(app, 'saved_l10n');
  final external = Directory(p.join(app, 'external_l10n'))..createSync();
  File(p.join(external.path, 'app_en.arb'))
      .writeAsStringSync('{"@@locale":"en","appTitle":"External"}');
  final router = File(p.join(app, 'lib/app/router.dart')).readAsStringSync();
  final metadata = File(p.join(app, 'flutter_forge.yaml')).readAsStringSync();
  Future<void> refuses() async {
    final result = await Process.run(executable, [
      'feature',
      'unsafe_codegen',
      '--project-dir',
      app,
      '--json',
    ], workingDirectory: cwd);
    if (result.exitCode != 1 ||
        Directory(p.join(app, 'lib/features/unsafe_codegen')).existsSync() ||
        File(p.join(app, 'lib/app/router.dart')).readAsStringSync() != router ||
        File(p.join(app, 'flutter_forge.yaml')).readAsStringSync() !=
            metadata ||
        external.listSync().length != 1) {
      throw StateError(
        'Unsafe codegen preflight failed: ${result.stdout} ${result.stderr}',
      );
    }
  }

  directory.renameSync(saved);
  final link = Link(directory.path)..createSync(external.path);
  await refuses();
  link.deleteSync();
  Directory(saved).renameSync(directory.path);
  final config = File(p.join(app, 'l10n.yaml'));
  final original = config.readAsStringSync();
  config.writeAsStringSync('${original}output-dir: ../external_l10n\n');
  await refuses();
  config.writeAsStringSync(original);
}

Future<void> verifyInit(String executable, String parent) async {
  final app = p.join(parent, 'adopt_existing');
  await run('flutter', [
    'create',
    '--empty',
    '--no-pub',
    '--platforms',
    'ios,android',
    app,
  ], parent);
  Map<String, String> snapshot() => {
    for (final entity in Directory(
      app,
    ).listSync(recursive: true, followLinks: false))
      if (entity is File)
        p.relative(entity.path, from: app): base64Encode(
          entity.readAsBytesSync(),
        ),
  };
  final before = snapshot();
  await run(executable, [
    'init',
    '--state',
    'provider',
    '--project-dir',
    app,
    '--json',
    '--dry-run',
  ], parent);
  if (jsonEncode(snapshot()) != jsonEncode(before)) {
    throw StateError('init dryrun mutated files');
  }
  final raw = await run(executable, [
    'init',
    '--state',
    'provider',
    '--project-dir',
    app,
    '--json',
  ], parent);
  final after = snapshot()..remove('flutter_forge.yaml');
  if (jsonEncode(after) != jsonEncode(before)) {
    throw StateError('init changed existing files');
  }
  final result = jsonDecode(raw) as Map<String, dynamic>;
  final data = result['data'] as Map<String, dynamic>;
  final missing = data['missingDependencies'] as Map<String, dynamic>;
  for (final command in (missing['commands'] as List<dynamic>).cast<String>()) {
    final args = RegExp(r"'([^']+)'")
        .allMatches(command.substring('flutter pub add '.length))
        .map((m) => m[1])
        .whereType<String>()
        .toList();
    await run('flutter', ['pub', 'add', ...args], app);
  }
  await run(executable, [
    'feature',
    'adopted',
    '--project-dir',
    app,
    '--json',
  ], parent);
  await run('flutter', ['analyze'], app);
  await run('flutter', ['test'], app);
  final scaffold = p.join(parent, 'adopt_scaffold');
  await run('flutter', [
    'create',
    '--empty',
    '--no-pub',
    '--platforms',
    'ios,android',
    scaffold,
  ], parent);
  final source = File(p.join(scaffold, 'lib/main.dart')).readAsStringSync();
  File(p.join(scaffold, 'pubspec.yaml')).writeAsStringSync(
    appPlan(
      DartName.parse('adopt_scaffold'),
      state: StateStyle.riverpod,
      lintProfile: LintProfile.flutter,
    ).files['pubspec.yaml']!,
  );
  await run(executable, [
    'init',
    '--scaffold',
    '--state',
    'riverpod',
    '--project-dir',
    scaffold,
    '--json',
  ], parent);
  if (File(p.join(scaffold, 'lib/main.dart')).readAsStringSync() != source) {
    throw StateError('Scaffold adoption overwrote the entrypoint');
  }
  await run(executable, [
    'feature',
    'adopted',
    '--project-dir',
    scaffold,
    '--json',
  ], parent);
  await run('flutter', ['analyze'], scaffold);
  await run('flutter', ['test'], scaffold);
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
