import 'profiles.dart';

/// Direct dependencies shared by both recipes, expressed as pubspec YAML.
const appDependencies = {
  'flutter': '{sdk: flutter}',
  'go_router': '^18.1.4',
  'material_ui': '^1.11.0',
};

const appDevDependencies = {'flutter_test': '{sdk: flutter}'};

Map<String, String> dependenciesFor(
  Recipe recipe, {
  StateStyle state = StateStyle.cubit,
  bool infrastructure = false,
}) => {
  ...appDependencies,
  if (infrastructure) ...{
    'dio': '^5.11.1',
    'get_it': '^9.3.0',
    'freezed_annotation': '^3.1.0',
    'json_annotation': '^4.12.0',
    'flutter_localizations': '{sdk: flutter}',
    'intl': 'any',
    'cupertino_ui': '^1.1.7',
  },
  if (state.usesBloc) 'flutter_bloc': '^9.1.1',
  if (state == StateStyle.riverpod) 'flutter_riverpod': '^3.5.0',
  if (state == StateStyle.provider) 'provider': '^6.1.5+1',
  if (recipe == Recipe.clean) 'fpdart': '^1.2.0',
};

Map<String, String> devDependenciesFor(
  LintProfile profile, {
  StateStyle state = StateStyle.cubit,
  bool infrastructure = false,
}) => {
  ...appDevDependencies,
  if (infrastructure) ...{
    'build_runner': '^2.17.1',
    'freezed': '^4.0.3',
    'json_serializable': '^6.15.2',
  },
  if (state.usesBloc) 'bloc_test': '^10.0.0',
  if (profile == LintProfile.flutter) 'flutter_lints': '^6.0.0',
  if (profile == LintProfile.veryGood) 'very_good_analysis': '^11.0.0',
};
