import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generation/generation_plan.dart';
import '../generation/codegen_preflight.dart';
import '../project/dependency_check.dart';
import '../project/names.dart';
import '../project/profiles.dart';
import '../project/project_config.dart';
import '../templates/app_templates.dart';
import '../toolchain/flutter_toolchain.dart';
import 'code_generation.dart';
import 'options.dart';
import 'reporter.dart';

Future<int> initializeProject(
  CommandOptions args,
  String cwd,
  CliReporter reporter,
  FlutterToolchain flutter,
) async {
  final root = canonicalRoot(p.join(cwd, args.projectDir));
  final name = ProjectConfig.readPackage(root);
  final recipe = Recipe.values.byName(args.recipe ?? 'clean');
  final profile = ProjectConfig.resolveLint(root, args.lintProfile ?? 'auto');
  final state = StateStyle.values.byName(args.state ?? 'cubit');
  validateAppName(
    name,
    recipe: recipe,
    profile: profile,
    state: state,
    infrastructure: args.scaffold,
  );
  var plan = GenerationPlan({
    configFileName: ProjectConfig(
      name,
      recipe: recipe,
      lintProfile: profile,
      state: state,
    ).encode(),
  });
  if (args.scaffold) {
    final files = Map<String, String>.of(
      appPlan(name, recipe: recipe, lintProfile: profile, state: state).files,
    );
    files.remove('pubspec.yaml');
    files.remove('analysis_options.yaml');
    files['lib/main_forge.dart'] = files.remove('lib/main.dart')!;
    files['test/forge_widget_test.dart'] = files.remove(
      'test/widget_test.dart',
    )!;
    plan = GenerationPlan(
      files,
      absentDirectories: [
        'lib/features/home',
        'test/features/home',
        'lib/l10n',
      ],
    );
  }
  final writer = FileWriter()..check(root, plan);
  final missing = MissingDependencies(
    root,
    recipe,
    profile,
    state: state,
    infrastructure: args.scaffold,
  );
  reporter.data.addAll({
    'operation': 'init',
    'name': name.value,
    'projectRoot': root,
    'recipe': recipe.name,
    'state': state.name,
    'lintProfile': profile.configName,
    'dryRun': args.dryRun,
    'scaffold': args.scaffold,
    'missingDependencies': missing.toJson(),
    'warnings': [if (!missing.isEmpty) missing.instructions],
    args.dryRun ? 'plannedFiles' : 'generatedFiles': plan.files.keys.toList(),
  });
  if (args.scaffold) {
    if (!missing.isEmpty) throw FormatException(missing.instructions);
    final pub = loadYaml(
      File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
    ) as YamlMap;
    final settings = pub['flutter'];
    final assets = settings is YamlMap ? settings['assets'] : null;
    if (settings is! YamlMap ||
        settings['generate'] != true ||
        assets is! YamlList ||
        !assets.contains('assets/images/') ||
        !assets.contains('assets/icons/')) {
      throw const FormatException(
        'Before init --scaffold, declare flutter.generate: true and flutter.assets entries assets/images/ and assets/icons/. No pubspec files were changed.',
      );
    }
    reportGeneration(reporter, enabled: args.pub);
    checkCodegenOutputs(root, name, pending: plan.files);
  }
  if (args.dryRun) {
    reporter.info(
      args.scaffold
          ? 'Dry run — no files or processes changed. Would add managed scaffold using lib/main_forge.dart.'
          : 'Dry run — no files or processes changed. Would write $configFileName only.',
    );
  } else {
    writer.write(root, plan);
    if (args.scaffold && args.pub) {
      reporter.data['partialOutput'] = true;
      await generateCode(flutter, root, reporter);
      reporter.data.remove('partialOutput');
    }
    reporter.info(
      args.scaffold
          ? 'Added managed scaffold for ${name.value}. Run flutter run -t lib/main_forge.dart. Existing entrypoint, pubspec, and analysis options were not replaced.'
          : 'Initialized metadata for ${name.value}. Existing source and dependency files were not changed.',
    );
  }
  reporter.info(missing.instructions);
  return reporter.finish();
}
