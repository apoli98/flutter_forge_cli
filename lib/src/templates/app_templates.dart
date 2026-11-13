import '../generation/generation_plan.dart';
import '../project/app_dependencies.dart';
import '../project/names.dart';
import '../project/project_config.dart';
import 'feature_templates.dart';

GenerationPlan appPlan(DartName name) {
  final home = featurePlan(name, DartName.parse('home'), routePath: '/');
  return GenerationPlan({
    configFileName: ProjectConfig(name).encode(),
    'pubspec.yaml':
        '''name: ${name.value}
description: A feature-first Flutter application.
publish_to: none
version: 1.0.0+1

environment:
  sdk: '>=3.13.0 <4.0.0'
  flutter: '>=3.47.0'

dependencies:
${_dependencyEntries(appDependencies)}

dev_dependencies:
${_dependencyEntries(appDevDependencies)}

flutter:
  uses-material-design: true
''',
    'lib/main.dart': '''import 'package:material_ui/material_ui.dart';

import 'app/app.dart';

void main() => runApp(const App());
''',
    'lib/app/app.dart':
        '''import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter();

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
    'lib/app/router.dart': '''import 'package:go_router/go_router.dart';

import '../features/home/home_route.dart';
import '../features/home/presentation/home_cubit.dart';

GoRouter createRouter() => GoRouter(
  routes: [
    homeRoute(createHomeCubit: HomeCubit.new),
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

void main() {
  testWidgets('app opens Home and increments the counter', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Count: 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Increment'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
''',
    ...home.files,
  }, absentDirectories: home.absentDirectories);
}

String _dependencyEntries(Map<String, String> dependencies) => dependencies
    .entries
    .map((entry) => '  ${entry.key}: ${entry.value}')
    .join('\n');
