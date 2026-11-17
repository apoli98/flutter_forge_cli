import '../generation/generation_plan.dart';
import '../project/app_dependencies.dart';
import '../project/names.dart';
import '../project/managed_feature.dart';
import '../project/profiles.dart';
import '../project/project_config.dart';
import '../project/route_path.dart';
import 'feature_templates.dart';
import 'infrastructure_templates.dart';
import 'managed_feature_templates.dart';
import 'managed_integration_templates.dart';
import 'template_format.dart';

GenerationPlan appPlan(
  DartName name, {
  Recipe recipe = Recipe.clean,
  LintProfile lintProfile = LintProfile.veryGood,
  StateStyle state = StateStyle.cubit,
  bool infrastructure = true,
}) {
  final homeName = DartName.parse('home');
  final home = infrastructure
      ? managedFeatureArtifact(
          name,
          homeName,
          style: state,
          recipe: recipe,
          routePath: '/',
        )
      : featureArtifact(
          name,
          DartName.parse('home'),
          routePath: '/',
          recipe: recipe,
          style: state,
        );
  final clean = recipe == Recipe.clean;
  return GenerationPlan(
    formatTemplates({
      configFileName: ProjectConfig(
        name,
        recipe: recipe,
        lintProfile: lintProfile,
        state: state,
        features: infrastructure
            ? [ManagedFeature(homeName, state, recipe, RoutePath.parse('/'))]
            : null,
      ).encode(),
      'analysis_options.yaml':
          '''include: package:${lintProfile == LintProfile.veryGood ? 'very_good_analysis/analysis_options.yaml' : 'flutter_lints/flutter.yaml'}
${lintProfile == LintProfile.veryGood ? '\n# Application code does not publish a documented library API.\nlinter:\n  rules:\n    public_member_api_docs: false\n' : ''}''',
      'pubspec.yaml':
          '''name: ${name.value}
description: A feature-first Flutter application.
publish_to: none
version: 1.0.0+1

environment:
  sdk: '>=3.14.0 <4.0.0'
  flutter: '>=3.50.0'

dependencies:
${_dependencyEntries(dependenciesFor(recipe, state: state, infrastructure: infrastructure))}

dev_dependencies:
${_dependencyEntries(devDependenciesFor(lintProfile, state: state, infrastructure: infrastructure))}

flutter:
  uses-material-design: true
${infrastructure ? '''  generate: true
  assets:
    - assets/images/
    - assets/icons/
''' : ''}
''',
      'lib/main.dart':
          '''import 'package:material_ui/material_ui.dart';

import 'package:${name.value}/app/app.dart';

void main() => runApp(const App());
''',
      'lib/app/app.dart':
          '''import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:${name.value}/app/router.dart';
import 'package:${name.value}/app/theme.dart';
${clean ? "import 'package:${name.value}/features/home/data/datasources/local_home_datasource.dart';" : ''}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter(${clean ? 'homeDatasource: const LocalHomeDatasource()' : ''});

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '${name.className}',
    theme: appTheme,
    routerConfig: _router,
  );
}
''',
      'lib/app/router.dart':
          '''import 'package:go_router/go_router.dart';

${home.wiring.imports.join('\n')}

GoRouter createRouter(${clean ? '{required HomeDatasource homeDatasource}' : ''}) => GoRouter(
  routes: [
    ${home.wiring.routeEntry}
  ],
);
''',
      'lib/app/theme.dart': '''import 'package:material_ui/material_ui.dart';

final appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315DA8)),
  useMaterial3: true,
);
''',
      'test/widget_test.dart':
          '''import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:${name.value}/app/app.dart';
${infrastructure ? "import 'package:${name.value}/l10n/app_localizations.dart';" : ''}

void main() {
  testWidgets('app opens Home${clean ? ' with explicit local content' : ' and increments the counter'}', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    ${infrastructure ? "expect(AppLocalizations.of(tester.element(find.text('Home'))).starterGreeting, 'Welcome to your app');" : ''}
    ${clean ? "expect(find.text('Welcome to your app'), findsOneWidget);" : """expect(find.text('Count: 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Increment'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);"""}
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''',
      if (clean)
        'lib/features/home/data/datasources/local_home_datasource.dart':
            '''import 'package:${name.value}/features/home/data/datasources/home_datasource.dart';
import 'package:${name.value}/features/home/data/models/home_model.dart';

/// Explicit local app content, not a pretend remote API.
final class LocalHomeDatasource implements HomeDatasource {
  const LocalHomeDatasource();

  @override
  Future<HomeModel> load() async => const HomeModel(id: 'home', title: 'Welcome to your app');
}
''',
      ...home.plan.files,
      if (infrastructure) ...{
        if (clean)
          'test/app/dependencies_test.dart':
              '''import 'package:flutter_test/flutter_test.dart';
import 'package:${name.value}/app/dependencies.dart';
import 'package:${name.value}/features/home/data/datasources/home_datasource.dart';
import 'package:${name.value}/features/home/data/models/home_model.dart';
import 'package:${name.value}/features/home/domain/usecases/load_home.dart';

final class _HomeDatasource implements HomeDatasource {
  const new();

  @override
  Future<HomeModel> load() async => const HomeModel(id: 'override', title: 'App-owned adapter');
}

void main() {
  test('composition accepts an app-owned adapter without editing managed files', () async {
    const datasource = _HomeDatasource();
    final services = createDependencies(homeDatasource: datasource);
    addTearDown(services.reset);
    expect(services<HomeDatasource>(), same(datasource));
    final result = await services<LoadHome>()();
    expect(result.fold((failure) => failure.message, (item) => item.title), 'App-owned adapter');
  });
}
''',
        ...infrastructureFiles(name),
        ...managedIntegrationFiles(name, [
          ManagedFeature(homeName, state, recipe, RoutePath.parse('/')),
        ]),
        'lib/app/app.dart':
            '''import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:${name.value}/app/dependencies.dart';
import 'package:${name.value}/app/router.dart';
import 'package:${name.value}/app/theme.dart';
import 'package:${name.value}/l10n/app_localizations.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GetIt _services = createDependencies();
  late final GoRouter _router = createRouter(_services);

  @override
  void dispose() {
    _router.dispose();
    unawaited(_services.reset());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: appTheme,
    routerConfig: _router,
  );
}
''',
      },
    }),
    absentDirectories: home.plan.absentDirectories,
  );
}

String _dependencyEntries(Map<String, String> dependencies) {
  final names = dependencies.keys.toList()..sort();
  return names.map((name) => '  $name: ${dependencies[name]}').join('\n');
}
