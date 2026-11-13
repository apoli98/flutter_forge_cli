import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/project_config.dart';
import 'options.dart';

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
      parsed?.name ?? await prompt.choose('Command', ['create', 'feature']);
  final suppliedName = parsed?.rest.singleOrNull;
  DartName checkName(String value) {
    final name = DartName.parse(value);
    if (command == 'create') validateAppName(name);
    return name;
  }

  final name = suppliedName ?? await prompt.value('Name', validate: checkName);
  checkName(name);

  Future<String> option(
    String flag,
    String label,
    String fallback,
    void Function(String) validate,
  ) async {
    if (parsed?.wasParsed(flag) == true || !interactive) {
      final value = parsed?.option(flag) ?? fallback;
      validate(value);
      return value;
    }
    return prompt.value(label, defaultValue: fallback, validate: validate);
  }

  final dryRun = commonFlag(args, 'dry-run');
  late CommandOptions result;
  if (command == 'create') {
    final org = await option(
      'org',
      'Organization',
      'com.example',
      validateOrganization,
    );
    final platforms = await option(
      'platforms',
      'Platforms (comma-separated)',
      'ios,android',
      parsePlatforms,
    );
    final output = await option('output', 'Existing output parent', '.', (
      value,
    ) {
      final path = p.normalize(p.join(cwd, value));
      if (!Directory(path).existsSync()) {
        throw FileSystemException(
          '--output must be an existing directory',
          path,
        );
      }
    });
    final pub = interactive && parsed?.wasParsed('pub') != true
        ? await prompt.choose('Fetch dependencies', ['yes', 'no']) == 'yes'
        : parsed?.flag('pub') ?? true;
    result = CommandOptions(
      command: command,
      name: name,
      dryRun: dryRun,
      org: org,
      platforms: platforms,
      output: output,
      pub: pub,
    );
  } else {
    final projectDir = await option(
      'project-dir',
      'Flutter Forge project directory',
      '.',
      (value) {
        ProjectConfig.read(canonicalRoot(p.join(cwd, value)));
      },
    );
    final state = interactive && parsed?.wasParsed('state') != true
        ? await prompt.choose('State management', ['cubit', 'bloc'])
        : parsed!.option('state')!;
    result = CommandOptions(
      command: command,
      name: name,
      dryRun: dryRun,
      projectDir: projectDir,
      state: state,
    );
  }
  if (interactive) {
    String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
    final options = command == 'create'
        ? '--org ${quote(result.org)} --platforms ${quote(result.platforms)} --output ${quote(p.normalize(p.join(cwd, result.output)))} ${result.pub ? '--pub' : '--no-pub'}'
        : '--project-dir ${quote(p.normalize(p.join(cwd, result.projectDir)))} --state ${result.state}';
    out.writeln(
      'Resolved command:\nflutter-forge $command $name $options${dryRun ? ' --dry-run' : ''}',
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
