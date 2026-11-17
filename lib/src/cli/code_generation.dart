import '../toolchain/flutter_toolchain.dart';
import '../generation/codegen_preflight.dart';
import '../project/project_config.dart';
import 'reporter.dart';

const generationCommands = [
  ['pub', 'get'],
  ['gen-l10n'],
  ['pub', 'run', 'tool/fix_localization_imports.dart'],
  ['pub', 'run', 'build_runner', 'build'],
];

void reportGeneration(CliReporter reporter, {required bool enabled}) {
  reporter.data['requiredCommands'] = [
    for (final command in generationCommands) ['flutter', ...command],
  ];
  reporter.data['codeGeneration'] = enabled ? 'requested' : 'required';
  if (!enabled) {
    reporter.info(
      'Dependencies not fetched; generated parts and localizations are required before analyze/run. Run:\n${generationCommands.map((command) => 'flutter ${command.join(' ')}').join('\n')}',
    );
  }
}

Future<void> generateCode(
  FlutterToolchain flutter,
  String root,
  CliReporter reporter,
) async {
  checkCodegenOutputs(root, ProjectConfig.read(root).name);
  for (final command in generationCommands) {
    reporter.data['failedStage'] = 'flutter ${command.join(' ')}';
    await flutter.run(command, workingDirectory: root);
  }
  reporter.data.remove('failedStage');
  reporter.data['codeGeneration'] = 'complete';
}
