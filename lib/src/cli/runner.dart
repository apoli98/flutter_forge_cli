import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../generation/generation_plan.dart';
import '../generation/codegen_preflight.dart';
import '../project/names.dart';
import '../project/managed_feature.dart';
import '../project/dependency_check.dart';
import '../project/profiles.dart';
import '../project/project_config.dart';
import '../project/route_path.dart';
import '../templates/app_templates.dart';
import '../templates/feature_templates.dart';
import '../templates/managed_feature_templates.dart';
import '../templates/managed_integration_templates.dart';
import '../toolchain/flutter_toolchain.dart';
import 'options.dart';
import 'command_definitions.dart';
import 'invocation_schema.dart';
import 'init_command.dart';
import 'prompt.dart';
import 'reporter.dart';
import 'code_generation.dart';

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
    final definition = cliCommands.commands[command?.name];
    if (commonFlag(args, 'help')) {
      _help(reporter, parser, command?.name);
      return reporter.finish();
    }
    if (commonFlag(args, 'schema')) {
      final schema = invocationSchema(parser, command: command?.name);
      reporter.data.addAll({'operation': 'schema', 'schema': schema});
      reporter.info(jsonEncode(schema));
      return reporter.finish();
    }
    if (args.rest.isNotEmpty ||
        (command?.rest.length ?? 0) > (definition?.maximumPositionals ?? 0)) {
      throw const FormatException(
        'Expected create <name>, feature <name>, or init (without a name).',
      );
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
    final missingName =
        command == null || command.rest.length < definition!.minimumPositionals;
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
    final flutter =
        toolchain ?? SystemFlutterToolchain(output: reporter.json ? err : out);
    if (options.command == 'init') {
      return await initializeProject(options, cwd, reporter, flutter);
    }
    final name = DartName.parse(options.name);
    switch (options.command) {
      case 'create':
        return await _create(options, name, cwd, flutter, reporter);
      case 'feature':
        return await _feature(options, name, cwd, reporter, flutter);
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
    String commandsWithNames(bool named) => cliCommands.commands.values
        .where((command) => command.positionals.isNotEmpty == named)
        .map((command) => '  ${command.usage.padRight(16)}${command.help}')
        .join('\n');
    out.writeln(
      'Usage: flutter-forge <command> [options]\n'
      '${commandsWithNames(true)}\n\n'
      '${commandsWithNames(false)}\n\n'
      '${parser.usage}\n\nUse flutter-forge <command> --help for command options.',
    );
  } else {
    out.writeln(
      'Usage: flutter-forge ${cliCommands.commands[command]!.usage} [options]\n'
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
  final recipe = Recipe.values.byName(args.recipe ?? 'clean');
  final state = StateStyle.values.byName(args.state ?? 'cubit');
  final profile = args.lintProfile == null || args.lintProfile == 'auto'
      ? LintProfile.veryGood
      : parseLintProfile(args.lintProfile!);
  validateAppName(
    name,
    recipe: recipe,
    profile: profile,
    state: state,
    infrastructure: true,
  );
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
    'recipe': recipe.name,
    'state': state.name,
    'lintProfile': profile.configName,
  });
  if (FileSystemEntity.typeSync(target, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Target must not exist (including symbolic links)',
      target,
    );
  }
  final plan = appPlan(
    name,
    recipe: recipe,
    lintProfile: profile,
    state: state,
  );
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
  reportGeneration(reporter, enabled: args.pub);
  if (args.dryRun) {
    reporter.data['plannedFiles'] = plan.files.keys.toList();
    reporter.info(
      'Dry run — no files or processes changed.\nflutter ${createArgs.join(' ')}',
    );
    reporter.info('Flutter also supplies the selected platform scaffold.');
    _preview(reporter, target, plan);
    if (args.pub) {
      reporter.info(
        'Then: ${generationCommands.map((command) => 'flutter ${command.join(' ')}').join('; ')} in $target',
      );
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
      await generateCode(flutter, target, reporter);
    }
  } on Exception catch (e) {
    stage = reporter.data['failedStage'] as String? ?? stage;
    reporter.diagnostic('Failed during $stage: $e');
    final partial =
        FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.notFound;
    reporter.data.addAll({
      'failedStage': stage,
      'partialOutput': partial,
      'scaffoldComplete':
          stage != 'flutter create' && stage != 'writing the app scaffold',
    });
    if (partial) {
      reporter.diagnostic(
        'Partial output remains at $target. Nothing was rolled back or deleted. '
        'Inspect it before retrying; create requires an absent target.',
      );
      if (stage != 'flutter create' && stage != 'writing the app scaffold') {
        reporter.data['retryArguments'] = [
          'flutter',
          ...generationCommands.firstWhere(
            (command) => 'flutter ${command.join(' ')}' == stage,
          ),
        ];
        reporter.diagnostic(
          'Scaffold is complete. Retry $stage in $target, then the remaining required commands.',
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
    reporter.info(
      'Run the required commands above in $target before starting the app.',
    );
  }
  return reporter.finish();
}

Future<int> _feature(
  CommandOptions args,
  DartName name,
  String cwd,
  CliReporter reporter,
  FlutterToolchain flutter,
) async {
  final root = canonicalRoot(p.join(cwd, args.projectDir));
  final config = ProjectConfig.read(root);
  final style = args.state == null
      ? config.state
      : StateStyle.values.byName(args.state!);
  final recipe = args.recipe == null
      ? config.recipe
      : Recipe.values.byName(args.recipe!);
  final profile = args.lintProfile == null
      ? config.lintProfile
      : ProjectConfig.resolveLint(root, args.lintProfile!);
  validateAppName(
    config.name,
    recipe: recipe,
    profile: profile,
    state: style,
    infrastructure: config.managed,
  );
  final artifact = config.managed
      ? managedFeatureArtifact(
          config.name,
          name,
          style: style,
          recipe: recipe,
          routePath: args.route ?? '/${name.value}',
        )
      : featureArtifact(
          config.name,
          name,
          style: style,
          recipe: recipe,
          routePath: args.route,
        );
  var plan = artifact.plan;
  final expected = <String, String>{};
  if (config.managed) {
    final feature = ManagedFeature(
      name,
      style,
      recipe,
      RoutePath.parse(args.route ?? '/${name.value}'),
    );
    if (config.features!.any(
      (existing) =>
          existing.name.value == name.value ||
          existing.name.className == name.className ||
          existing.route.value.toLowerCase() ==
              feature.route.value.toLowerCase(),
    )) {
      throw const FormatException(
        'Managed feature name, symbol, or route already registered.',
      );
    }
    final next = [...config.features!, feature];
    expected.addAll(managedIntegrationFiles(config.name, config.features!));
    expected[configFileName] = config.encode();
    plan = GenerationPlan({
      ...plan.files,
      ...managedIntegrationFiles(config.name, next),
      configFileName: ProjectConfig(
        config.name,
        recipe: config.recipe,
        lintProfile: config.lintProfile,
        state: config.state,
        features: next,
      ).encode(),
    }, absentDirectories: plan.absentDirectories);
  }
  reporter.data.addAll({
    'operation': 'feature',
    'name': name.value,
    'projectRoot': root,
    'state': style.name,
    'dryRun': args.dryRun,
    'registered': false,
    'registrationStatus': config.managed ? 'planned' : 'manual',
    'recipe': recipe.name,
    'lintProfile': profile.configName,
    'wiring': artifact.wiring.toJson(),
  });
  final missing = MissingDependencies(
    root,
    recipe,
    profile,
    state: style,
    infrastructure: config.managed,
  );
  reporter.data['missingDependencies'] = missing.toJson();
  if (!missing.isEmpty) throw FormatException(missing.instructions);
  final writer = FileWriter();
  if (config.managed) {
    checkCodegenOutputs(root, config.name);
    writer.checkManaged(root, plan, expected);
    reportGeneration(reporter, enabled: args.pub);
  } else {
    writer.check(root, plan);
  }
  if (args.dryRun) {
    reporter.data['plannedFiles'] = plan.files.keys.toList();
    reporter.info('Dry run — no files or processes changed.');
    reporter.data['updatedFiles'] = expected.keys.toList();
    _preview(reporter, root, plan);
    reporter.info(
      config.managed
          ? 'Would generate and register routes and DI.'
          : 'Would generate, not register.',
    );
  } else {
    try {
      if (config.managed) {
        writer.writeManaged(root, plan, expected);
      } else {
        writer.write(root, plan);
      }
    } on FileSystemException catch (e) {
      reporter.data['partialOutput'] = true;
      throw FileSystemException(
        '${e.message}. Generation may be partial at $root; nothing was rolled back. Inspect before retrying.',
        e.path,
        e.osError,
      );
    }
    reporter.data['generatedFiles'] = plan.files.keys
        .where((path) => !expected.containsKey(path))
        .toList();
    reporter.data['updatedFiles'] = expected.keys.toList();
    reporter.data['registered'] = config.managed;
    reporter.data['registrationStatus'] = config.managed
        ? 'registered'
        : 'manual';
    if (config.managed && args.pub) {
      reporter.data['partialOutput'] = true;
      await generateCode(flutter, root, reporter);
      reporter.data.remove('partialOutput');
    }
    reporter.info(
      'Generated${config.managed ? ' and registered' : ', not registered'}: ${name.value} (${style.name}).',
    );
  }
  if (!config.managed) reporter.info(artifact.wiring.text);
  return reporter.finish();
}

void _preview(CliReporter reporter, String root, GenerationPlan plan) {
  reporter.info('Planned template files in $root:');
  for (final path in plan.files.keys) {
    reporter.info('  $path');
  }
}
