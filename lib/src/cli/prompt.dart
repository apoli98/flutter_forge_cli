import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/app_dependencies.dart';
import '../project/profiles.dart';
import '../project/project_config.dart';
import '../project/route_path.dart';
import 'options.dart';
import 'command_definitions.dart';

/// Injectable terminal capability and asynchronous line input. No raw mode.
final class PromptInput {
  PromptInput({required this.hasTerminal, required this.readLine, this.close});

  factory PromptInput.system() {
    StreamIterator<String>? lines;
    return PromptInput(
      hasTerminal: stdin.hasTerminal && stdout.hasTerminal,
      readLine: () async {
        lines ??= StreamIterator(
          stdin.transform(utf8.decoder).transform(const LineSplitter()),
        );
        return await lines!.moveNext() ? lines!.current : null;
      },
      close: () async => lines?.cancel(),
    );
  }

  final bool hasTerminal;
  final Future<String?> Function() readLine;
  final Future<void> Function()? close;
}

final class PromptCancelled implements Exception {
  const PromptCancelled();
}

bool isCi(Map<String, String> environment) {
  final value = environment['CI']?.trim().toLowerCase();
  return value != null && value.isNotEmpty && value != 'false' && value != '0';
}

Future<CommandOptions> collectOptions(
  ArgResults args,
  String cwd, {
  required bool interactive,
  required PromptInput input,
  required StringSink out,
}) async {
  final prompt = _Prompt(input, out);
  final parsed = args.command;
  final command =
      parsed?.name ??
      await prompt.choose('Command', cliCommands.commands.keys.toList());
  final parserOptions = cliParser().commands[command]!.options;
  String defaultValue(String flag) => parserOptions[flag]!.defaultsTo as String;
  List<String> choices(String flag) {
    final option = parserOptions[flag]!;
    return [
      if (option.defaultsTo != null) option.defaultsTo as String,
      ...option.allowed!.where((value) => value != option.defaultsTo),
    ];
  }

  final suppliedName = parsed?.rest.singleOrNull;
  DartName checkName(String value) {
    final name = DartName.parse(value);
    if (command == 'create') {
      // Backend and profile dependencies are checked once all choices resolve.
      if (appDependencies.containsKey(value) ||
          appDevDependencies.containsKey(value)) {
        throw FormatException(
          'App name "$value" conflicts with a bundled direct dependency. Choose a different package name.',
        );
      }
    }
    return name;
  }

  var name = command == 'init'
      ? ''
      : suppliedName ?? await prompt.value('Name', validate: checkName);
  if (command != 'init') checkName(name);

  Future<String> option(
    String flag,
    String label,
    void Function(String) validate,
  ) async {
    final fallback = defaultValue(flag);
    if (parsed?.wasParsed(flag) == true || !interactive) {
      final value = parsed?.option(flag) ?? fallback;
      validate(value);
      return value;
    }
    return prompt.value(label, defaultValue: fallback, validate: validate);
  }

  final dryRun = commonFlag(args, 'dry-run');
  Future<String?> profile(String flag) async {
    if (parsed?.wasParsed(flag) == true) return parsed!.option(flag);
    if (interactive && command != 'feature') {
      return prompt.choose(flag, choices(flag));
    }
    return parsed?.option(flag);
  }

  // Resolve profiles after basic paths/options so explicit invalid paths fail first.
  late CommandOptions result;
  if (command == 'create') {
    final org = await option('org', 'Organization', validateOrganization);
    final platforms = await option(
      'platforms',
      'Platforms (comma-separated)',
      parsePlatforms,
    );
    final output = await option('output', 'Existing output parent', (value) {
      final path = p.normalize(p.join(cwd, value));
      if (!Directory(path).existsSync()) {
        throw FileSystemException(
          '--output must be an existing directory',
          path,
        );
      }
    });
    final defaultPub = parserOptions['pub']!.defaultsTo as bool;
    final pub = interactive && parsed?.wasParsed('pub') != true
        ? await prompt.choose('Fetch dependencies', [
                if (defaultPub) ...['yes', 'no'] else ...['no', 'yes'],
              ]) ==
              'yes'
        : parsed?.flag('pub') ?? defaultPub;
    final state = await profile('state');
    final recipe = await profile('recipe');
    final lintProfile = await profile('lint-profile');
    void checkResolvedName(String value) => validateAppName(
      DartName.parse(value),
      recipe: Recipe.values.byName(recipe ?? 'clean'),
      state: StateStyle.values.byName(state ?? 'cubit'),
      profile: lintProfile == null || lintProfile == 'auto'
          ? LintProfile.veryGood
          : parseLintProfile(lintProfile),
      infrastructure: true,
    );
    try {
      checkResolvedName(name);
    } on FormatException catch (e) {
      if (!interactive || suppliedName != null) rethrow;
      out.writeln('Invalid input: ${e.message}');
      name = await prompt.value('Name', validate: checkResolvedName);
    }
    result = CommandOptions(
      command: command,
      name: name,
      dryRun: dryRun,
      org: org,
      platforms: platforms,
      output: output,
      pub: pub,
      state: state,
      recipe: recipe,
      lintProfile: lintProfile,
    );
  } else {
    final projectDir = await option(
      'project-dir',
      'Flutter Forge project directory',
      (value) {
        final root = canonicalRoot(p.join(cwd, value));
        if (command == 'init') {
          ProjectConfig.readPackage(root);
        } else {
          ProjectConfig.read(root);
        }
      },
    );
    final inheritedState = command == 'feature'
        ? ProjectConfig.read(canonicalRoot(p.join(cwd, projectDir))).state
        : StateStyle.cubit;
    final state = interactive && parsed?.wasParsed('state') != true
        ? await prompt.choose('State management', [
            inheritedState.name,
            ...choices('state').where((state) => state != inheritedState.name),
          ])
        : parsed?.option('state');
    final route = command == 'feature' ? parsed?.option('route') : null;
    if (route != null) RoutePath.parse(route);
    result = CommandOptions(
      command: command,
      name: name,
      dryRun: dryRun,
      projectDir: projectDir,
      state: state,
      recipe: await profile('recipe'),
      lintProfile: await profile('lint-profile'),
      route: route,
      scaffold: command == 'init' && (parsed?.flag('scaffold') ?? false),
      pub: parsed?.flag('pub') ?? parserOptions['pub']!.defaultsTo as bool,
    );
  }
  if (interactive) {
    String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
    final options = command == 'create'
        ? '--org ${quote(result.org)} --platforms ${quote(result.platforms)} --output ${quote(p.normalize(p.join(cwd, result.output)))} ${result.pub ? '--pub' : '--no-pub'}'
        : '--project-dir ${quote(p.normalize(p.join(cwd, result.projectDir)))}${result.scaffold ? ' --scaffold' : ''}${command == 'feature' || result.scaffold ? (result.pub ? ' --pub' : ' --no-pub') : ''}';
    final profiles =
        '${result.state == null ? '' : ' --state ${result.state}'}'
        '${result.recipe == null ? '' : ' --recipe ${result.recipe}'}'
        '${result.lintProfile == null ? '' : ' --lint-profile ${result.lintProfile}'}'
        '${result.route == null ? '' : ' --route ${quote(result.route!)}'}';
    out.writeln(
      'Resolved command:\nflutter-forge $command${name.isEmpty ? '' : ' $name'} $options$profiles${dryRun ? ' --dry-run' : ''}',
    );
    if (await prompt.choose('Proceed', ['no', 'yes']) != 'yes') {
      throw const PromptCancelled();
    }
  }
  return result;
}

final class _Prompt {
  _Prompt(this.input, this.out);
  final PromptInput input;
  final StringSink out;

  Future<String> value(
    String label, {
    String? defaultValue,
    required void Function(String) validate,
  }) async {
    while (true) {
      out.write('$label${defaultValue == null ? '' : ' [$defaultValue]'}: ');
      final line = await input.readLine();
      if (line == null) throw const PromptCancelled();
      final value = line.trim().isEmpty ? defaultValue ?? '' : line.trim();
      try {
        validate(value);
        return value;
      } on FormatException catch (e) {
        out.writeln('Invalid input: ${e.message}');
      } on FileSystemException catch (e) {
        out.writeln('Invalid input: ${e.message}: ${e.path}');
      }
    }
  }

  Future<String> choose(String label, List<String> choices) async {
    out.writeln('$label:');
    for (var i = 0; i < choices.length; i++) {
      out.writeln('  ${i + 1}) ${choices[i]}');
    }
    final selected = await value(
      'Select',
      defaultValue: '1',
      validate: (value) {
        final number = int.tryParse(value);
        if (!choices.contains(value) &&
            (number == null || number < 1 || number > choices.length)) {
          throw FormatException(
            'Choose 1-${choices.length} (${choices.join(', ')}).',
          );
        }
      },
    );
    return choices.contains(selected)
        ? selected
        : choices[int.parse(selected) - 1];
  }
}
