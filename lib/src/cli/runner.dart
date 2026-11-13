import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/project_config.dart';
import '../templates/app_templates.dart';
import '../templates/feature_templates.dart';
import '../toolchain/flutter_toolchain.dart';
import 'options.dart';
import 'prompt.dart';
import 'reporter.dart';

const version = '0.1.0';

Future<int> runCli(
  List<String> arguments, {
  StringSink? output,
  StringSink? error,
  String? workingDirectory,
  FlutterToolchain? toolchain,
  PromptInput? promptInput,
  Map<String, String>? environment,
}) async {
  final out = output ?? stdout;
  final err = error ?? stderr;
  final cwd = p.absolute(workingDirectory ?? Directory.current.path);
  final reporter = CliReporter(out, err);
  // Select error encoding even when parsing fails. This never rewrites tokens.
  reporter.json = arguments.takeWhile((arg) => arg != '--').contains('--json');
  final parser = cliParser();
  final input =
      promptInput ??
      (output == null
          ? PromptInput.system()
          : PromptInput(hasTerminal: false, readLine: () async => null));
  try {
    final args = parser.parse(arguments);
    reporter.json = commonFlag(args, 'json');
    reporter.command = args.command?.name;
    if (commonFlag(args, 'version')) {
      reporter.data.addAll({'operation': 'version', 'version': version});
      reporter.info('flutter-forge $version');
      return reporter.finish();
    }
    final command = args.command;
    if (commonFlag(args, 'help')) {
      _help(reporter, parser, command?.name);
      return reporter.finish();
    }
    if (args.rest.isNotEmpty || (command?.rest.length ?? 0) > 1) {
      throw const FormatException('Expected create <name> or feature <name>.');
    }
    final explicit = commonFlag(args, 'interactive');
    final disabled = commonFlag(args, 'no-interactive');
    if (explicit && (disabled || reporter.json)) {
      throw const FormatException(
        '--interactive conflicts with --no-interactive and --json.',
      );
    }
    if (explicit && !input.hasTerminal) {
      throw const FormatException(
        '--interactive requires terminal stdin and stdout. Use --no-interactive with create <name> or feature <name> and explicit options.',
      );
    }
    final missingName = command == null || command.rest.isEmpty;
    final interactive =
        explicit ||
        (!disabled &&
            !reporter.json &&
            input.hasTerminal &&
            !isCi(environment ?? Platform.environment) &&
            (arguments.isEmpty || (command != null && missingName)));
    if (!interactive && missingName) {
      if (arguments.isEmpty) {
        _help(reporter, parser, null);
        return reporter.finish();
      }
      throw FormatException(
        command == null
            ? 'Missing command and positional <name>. Expected create <name> [--org --platforms --output --pub] or feature <name> [--project-dir --state].'
            : 'Missing positional <name> for ${command.name}. Use flutter-forge ${command.name} <name> with --no-interactive, or --interactive in a terminal.',
      );
    }
    final options = await collectOptions(
      args,
      cwd,
      interactive: interactive,
      input: input,
      out: out,
    );
    reporter.command = options.command;
    final name = DartName.parse(options.name);
    final flutter =
        toolchain ?? SystemFlutterToolchain(output: reporter.json ? err : out);
    switch (options.command) {
      case 'create':
        return await _create(options, name, cwd, flutter, reporter);
      case 'feature':
        return _feature(options, name, cwd, reporter);
      default:
        throw const FormatException('Unknown command.');
    }
  } on FormatException catch (e) {
    reporter.diagnostic(
      'Error: ${e.message}\nUse flutter-forge --help for usage.',
    );
    return reporter.finish(exitCode: 64, kind: 'usage', message: e.message);
  } on FileSystemException catch (e) {
    reporter.diagnostic('Error: $e');
    return reporter.finish(exitCode: 1, kind: 'filesystem', message: '$e');
  } on ProcessException catch (e) {
    reporter.diagnostic('Error: $e');
    return reporter.finish(exitCode: 1, kind: 'process', message: '$e');
  } on PromptCancelled {
    reporter.diagnostic('Cancelled. No files or processes changed.');
    return reporter.finish(
      exitCode: 130,
      kind: 'cancelled',
      message: 'Cancelled before generation.',
    );
  } finally {
    await input.close?.call();
  }
}

void _help(CliReporter reporter, ArgParser parser, String? command) {
  final out = StringBuffer(
    'Flutter Forge $version — feature-first Flutter scaffolding.\n',
  );
  if (command == null) {
    out.writeln(
      'Usage: flutter-forge <command> [options]\n'
      '  create <name>   Create a new app in an absent directory.\n'
      '  feature <name>  Generate a feature; registration remains manual.\n\n'
      '${parser.usage}\n\nUse flutter-forge <command> --help for command options.',
    );
  } else {
    out.writeln(
      'Usage: flutter-forge $command <name> [options]\n'
      '${parser.commands[command]!.usage}',
    );
  }
  reporter.data.addAll({
    'operation': 'help',
    'version': version,
    'usage': out.toString(),
    'commands': parser.commands.keys.toList(),
    'options': (command == null ? parser : parser.commands[command]!)
        .options
        .keys
        .toList(),
  });
  reporter.info(out.toString().trimRight());
}

Future<int> _create(
  CommandOptions args,
  DartName name,
  String cwd,
  FlutterToolchain flutter,
  CliReporter reporter,
) async {
  validateAppName(name);
  final org = args.org;
  validateOrganization(org);
  final platforms = parsePlatforms(args.platforms);
  final selectedParent = p.normalize(p.join(cwd, args.output));
  if (!Directory(selectedParent).existsSync()) {
    throw FileSystemException(
      '--output must be an existing directory',
      selectedParent,
    );
  }
  final parent = canonicalRoot(selectedParent);
  final target = p.join(parent, name.value);
  reporter.data.addAll({
    'operation': 'create',
    'name': name.value,
    'target': target,
    'org': org,
    'platforms': platforms,
    'pub': args.pub,
    'dryRun': args.dryRun,
  });
  if (FileSystemEntity.typeSync(target, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Target must not exist (including symbolic links)',
      target,
    );
  }
  final plan = appPlan(name);
  final writer = FileWriter();
  writer.check(target, plan);
  final createArgs = [
    'create',
    '--empty',
    '--no-pub',
    '--project-name',
    name.value,
    '--org',
    org,
    '--platforms',
    platforms.join(','),
    target,
  ];
  reporter.data['flutterCreateArguments'] = createArgs;
  if (args.dryRun) {
    reporter.data['plannedFiles'] = plan.files.keys.toList();
    reporter.info(
      'Dry run — no files or processes changed.\nflutter ${createArgs.join(' ')}',
    );
    reporter.info('Flutter also supplies the selected platform scaffold.');
    _preview(reporter, target, plan);
    if (args.pub) {
      reporter.info('Then: flutter pub get in $target');
    }
    return reporter.finish();
  }
  var stage = 'flutter create';
  try {
    await flutter.run(createArgs, workingDirectory: parent);
    if (!Directory(target).existsSync()) {
      throw FileSystemException(
        'flutter create did not produce its target directory',
        target,
      );
    }
    stage = 'writing the app scaffold';
    writer.writeFreshApp(target, plan);
    stage = 'flutter pub get';
    if (args.pub) {
      await flutter.run(['pub', 'get'], workingDirectory: target);
    }
  } on Exception catch (e) {
    reporter.diagnostic('Failed during $stage: $e');
    final partial =
        FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.notFound;
    reporter.data.addAll({
      'failedStage': stage,
      'partialOutput': partial,
      'scaffoldComplete': stage == 'flutter pub get',
    });
    if (partial) {
      reporter.diagnostic(
        'Partial output remains at $target. Nothing was rolled back or deleted. '
        'Inspect it before retrying; create requires an absent target.',
      );
      if (stage == 'flutter pub get') {
        reporter.data['retryArguments'] = ['flutter', 'pub', 'get'];
        reporter.diagnostic(
          'Scaffold is complete. Retry flutter pub get in $target.',
        );
      }
    } else {
      reporter.diagnostic('No target output was created at $target.');
    }
    return reporter.finish(
      exitCode: 1,
      kind: e is ProcessException ? 'process' : 'filesystem',
      message: '$e',
    );
  }
  reporter.data['generatedFiles'] = plan.files.keys.toList();
  reporter.info('Created ${name.value} at $target.');
  if (!args.pub) {
    reporter.info('Dependencies not fetched. Run flutter pub get in $target.');
  }
  return reporter.finish();
}

int _feature(
  CommandOptions args,
  DartName name,
  String cwd,
  CliReporter reporter,
) {
  final root = canonicalRoot(p.join(cwd, args.projectDir));
  final config = ProjectConfig.read(root);
  final style = StateStyle.values.byName(args.state);
  final plan = featurePlan(config.name, name, style: style);
  reporter.data.addAll({
    'operation': 'feature',
    'name': name.value,
    'projectRoot': root,
    'state': style.name,
    'dryRun': args.dryRun,
    'registered': false,
    'wiring': {
      'routerFile': 'lib/app/router.dart',
      'imports': [
        "import '../features/${name.value}/${name.value}_route.dart';",
        "import '../features/${name.value}/presentation/${name.value}_${style.name}.dart';",
      ],
      'routeEntry':
          '${name.memberName}Route(create${name.className}${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}: ${name.className}${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}.new),',
      'location': '/${name.value}',
    },
  });
  final writer = FileWriter();
  writer.check(root, plan);
  if (args.dryRun) {
    reporter.data['plannedFiles'] = plan.files.keys.toList();
    reporter.info('Dry run — no files or processes changed.');
    _preview(reporter, root, plan);
    reporter.info('Would generate, not register.');
  } else {
    try {
      writer.write(root, plan);
    } on FileSystemException catch (e) {
      reporter.data['partialOutput'] = true;
      throw FileSystemException(
        '${e.message}. Generation may be partial at $root; nothing was rolled back. Inspect before retrying.',
        e.path,
        e.osError,
      );
    }
    reporter.data['generatedFiles'] = plan.files.keys.toList();
    reporter.info('Generated, not registered: ${name.value} (${style.name}).');
  }
  reporter.info(featureWiring(name, style));
  return reporter.finish();
}

void _preview(CliReporter reporter, String root, GenerationPlan plan) {
  reporter.info('Planned template files in $root:');
  for (final path in plan.files.keys) {
    reporter.info('  $path');
  }
}
