import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/profiles.dart';
import '../project/route_path.dart';
import 'clean_feature_templates.dart';
import 'notifier_feature_test_templates.dart';
import 'template_format.dart';

GenerationPlan notifierFeaturePlan(
  DartName package,
  DartName name,
  StateStyle style,
  Recipe recipe,
  RoutePath location,
) {
  final n = name.value;
  final c = name.className;
  final member = name.memberName;
  final prefix = 'package:${package.value}/features/$n';
  final base = 'lib/features/$n';
  final clean = recipe == Recipe.clean;
  final riverpod = style == StateStyle.riverpod;
  final state = clean ? '${c}State' : 'int';
  final initial = clean ? 'const ${c}Loading()' : '0';
  final controller = '${c}Notifier';
  final file = riverpod ? 'riverpod' : 'provider';
  final read = riverpod
      ? 'ref.read(${member}Provider.notifier)'
      : 'state_management.ReadContext(context).read<$controller>()';
  return GenerationPlan(
    formatTemplates({
      if (clean) ...{
        ...cleanDomainFiles(package, name),
        '$base/presentation/${n}_state.dart': cleanStateFile(package, name),
      },
      '$base/presentation/${n}_$file.dart':
          '''${clean ? "import 'dart:async';\n\n" : ''}import 'package:${riverpod ? 'flutter_riverpod/flutter_riverpod.dart' : 'material_ui/material_ui.dart'}' as ${riverpod ? 'state_management' : 'ui'};
${clean ? "import '$prefix/domain/usecases/load_$n.dart';\nimport '$prefix/presentation/${n}_state.dart';" : ''}

${riverpod ? '''final ${member}Provider = state_management.NotifierProvider<$controller, $state>(
  () => throw StateError('Use the route factory to provide this notifier.'),
  isAutoDispose: true,
  dependencies: const [],
);
''' : ''}
final class $controller extends ${riverpod ? 'state_management.Notifier<$state>' : 'ui.ChangeNotifier'} {
  $controller(${clean ? 'this._load' : ''});

${clean ? '  final Load$c _load;\n  int _request = 0;\n' : ''}${riverpod ? '''  @override
  $state build() {
    ${clean ? "ref.onDispose(() { _request++; });\n    unawaited(Future<void>.microtask(load));" : ''}
    return $initial;
  }
''' : '''  $state _state = $initial;
  $state get state => _state;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    ${clean ? '_request++;' : ''}
    super.dispose();
  }

  void _setState($state value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }
'''}
${clean ? '''  Future<void> load() async {
    if (${riverpod ? '!ref.mounted' : '_disposed'}) return;
    final request = ++_request;
    ${riverpod ? 'state = const ${c}Loading();' : '_setState(const ${c}Loading());'}
    final result = await _load();
    if (${riverpod ? '!ref.mounted' : '_disposed'} || request != _request) return;
    ${riverpod ? 'state = result.fold(${c}Failed.new, ${c}Loaded.new);' : '_setState(result.fold(${c}Failed.new, ${c}Loaded.new));'}
  }
''' : '''  void increment() {
    ${riverpod ? 'state++;' : '_setState(_state + 1);'}
  }
'''}
}
''',
      '$base/${n}_route.dart':
          '''${clean && !riverpod ? "import 'dart:async';\n\n" : ''}import 'package:${riverpod ? 'flutter_riverpod/flutter_riverpod.dart' : 'provider/provider.dart'}' as state_management;
import 'package:go_router/go_router.dart';
import '$prefix/presentation/${n}_$file.dart';
import '$prefix/presentation/${n}_page.dart';

GoRoute ${member}Route({required $controller Function() create$controller}) => GoRoute(
  path: '${location.value}',
  builder: (context, state) => ${riverpod ? '''state_management.ProviderScope(
    overrides: [${member}Provider.overrideWith(create$controller)],
    child: const ${c}Page(),
  )''' : '''state_management.ChangeNotifierProvider(
    create: (_) {
      final controller = create$controller();
      ${clean ? 'unawaited(controller.load());' : ''}
      return controller;
    },
    child: const ${c}Page(),
  )'''},
);
''',
      '$base/presentation/${n}_page.dart':
          '''${clean ? "import 'dart:async';\n\n" : ''}import 'package:${riverpod ? 'flutter_riverpod/flutter_riverpod.dart' : 'provider/provider.dart'}' as state_management;
import 'package:material_ui/material_ui.dart' as ui;
import '$prefix/presentation/${n}_$file.dart';
${clean ? "import '$prefix/presentation/${n}_state.dart';" : ''}

class ${c}Page extends ${riverpod ? 'state_management.ConsumerWidget' : 'ui.StatelessWidget'} {
  const ${c}Page({super.key});

  @override
  ui.Widget build(ui.BuildContext context${riverpod ? ', state_management.WidgetRef ref' : ''}) {
    final state = ${riverpod ? 'ref.watch(${member}Provider)' : 'state_management.WatchContext(context).watch<$controller>().state'};
    return ui.Scaffold(
      appBar: ui.AppBar(title: const ui.Text('$c')),
      body: ui.Center(
        child: ${clean ? '''switch (state) {
          ${c}Loading() => const ui.CircularProgressIndicator(),
          ${c}Loaded(:final item) => ui.Text(item.title),
          ${c}Failed(:final failure) => ui.Column(
            mainAxisSize: ui.MainAxisSize.min,
            children: [
              ui.Text(failure.message),
              ui.TextButton(
                onPressed: () { unawaited($read.load()); },
                child: const ui.Text('Retry'),
              ),
            ],
          ),
        }''' : "ui.Text('Count: \$state')"},
      ),
      ${clean ? '' : '''floatingActionButton: ui.FloatingActionButton(
        onPressed: () => $read.increment(),
        tooltip: 'Increment',
        child: const ui.Icon(ui.Icons.add),
      ),'''}
    );
  }
}
''',
      ...notifierFeatureTests(package, name, style, recipe, location),
    }),
    absentDirectories: [base, 'test/features/$n'],
  );
}
