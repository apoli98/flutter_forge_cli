import '../project/names.dart';
import '../project/profiles.dart';
import '../project/route_path.dart';

Map<String, String> notifierFeatureTests(
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
  final clean = recipe == Recipe.clean;
  final riverpod = style == StateStyle.riverpod;
  final controller = '${c}Notifier';
  final exitLocation = location.value == '/_forge_empty'
      ? '/_forge_other'
      : '/_forge_empty';
  final create =
      '$controller(${clean ? 'Load$c(${c}RepositoryImpl(datasource))' : ''})';
  final factory = clean ? '() => $create' : '$controller.new';
  return {
    'test/features/$n/${n}_test.dart':
        '''${clean ? "import 'dart:async';\n\n" : ''}import 'package:flutter_test/flutter_test.dart';
${riverpod ? "import 'package:flutter_riverpod/flutter_riverpod.dart' as state_management;" : ''}
import '$prefix/presentation/${n}_${style.name}.dart';
${clean ? '''import '$prefix/data/datasources/${n}_datasource.dart';
import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/data/models/${n}_model.dart';
import '$prefix/data/repositories/${n}_repository_impl.dart';
import '$prefix/domain/usecases/load_$n.dart';
import '$prefix/presentation/${n}_state.dart';

final class _Datasource implements ${c}Datasource {
  Future<${c}Model> Function() response = () async => const ${c}Model(id: '1', title: 'Starter');
  @override
  Future<${c}Model> load() => response();
}
''' : ''}
void main() {
  test('${clean ? 'loads, fails and retries' : 'increments the counter'}', () async {
    ${clean ? 'final datasource = _Datasource();' : ''}
    ${riverpod ? '''final container = state_management.ProviderContainer(overrides: [${member}Provider.overrideWith($factory)]);
    addTearDown(container.dispose);
    final subscription = container.listen(${member}Provider, (_, _) {});
    addTearDown(subscription.close);
    final controller = container.read(${member}Provider.notifier);
    ${clean ? 'await Future<void>.delayed(Duration.zero);' : ''}''' : '''final controller = $create;
    addTearDown(controller.dispose);'''}
    ${clean ? '''await controller.load();
    expect(${riverpod ? 'container.read(${member}Provider)' : 'controller.state'}, isA<${c}Loaded>());
    datasource.response = () async => throw const ${c}DataException('Offline');
    await controller.load();
    expect((${riverpod ? 'container.read(${member}Provider)' : 'controller.state'} as ${c}Failed).failure.message, 'Offline');
    datasource.response = () async => const ${c}Model(id: '2', title: 'Retried');
    await controller.load();
    expect((${riverpod ? 'container.read(${member}Provider)' : 'controller.state'} as ${c}Loaded).item.title, 'Retried');
    datasource.response = () async => throw StateError('bug');
    await expectLater(controller.load(), throwsStateError);''' : '''expect(${riverpod ? 'container.read(${member}Provider)' : 'controller.state'}, 0);
    controller.increment();
    expect(${riverpod ? 'container.read(${member}Provider)' : 'controller.state'}, 1);'''}
  });
${clean ? '''
  test('mapping validates the starter payload and bugs propagate', () async {
    expect(${c}Model.fromJson({'id': '1', 'title': 'Starter'}).toEntity().title, 'Starter');
    expect(() => ${c}Model.fromJson({'id': 1}), throwsA(isA<${c}DataException>()));
    final datasource = _Datasource()..response = () async => throw StateError('bug');
    await expectLater(${c}RepositoryImpl(datasource).load(), throwsStateError);
  });

  test('latest request wins and disposal ignores pending results', () async {
    final datasource = _Datasource();
    ${riverpod ? '''final container = state_management.ProviderContainer(overrides: [${member}Provider.overrideWith(() => $create)]);
    final subscription = container.listen(${member}Provider, (_, _) {});
    final controller = container.read(${member}Provider.notifier);
    await Future<void>.delayed(Duration.zero);''' : 'final controller = $create;'}
    final first = Completer<${c}Model>();
    final second = Completer<${c}Model>();
    datasource.response = () => first.future;
    final older = controller.load();
    datasource.response = () => second.future;
    final newer = controller.load();
    second.complete(const ${c}Model(id: '2', title: 'Newer'));
    await newer;
    first.complete(const ${c}Model(id: '1', title: 'Older'));
    await older;
    expect((${riverpod ? 'container.read(${member}Provider)' : 'controller.state'} as ${c}Loaded).item.title, 'Newer');
    final pending = Completer<${c}Model>();
    datasource.response = () => pending.future;
    final loading = controller.load();
    ${riverpod ? 'subscription.close();\n    container.dispose();' : 'controller.dispose();'}
    pending.complete(const ${c}Model(id: '3', title: 'Late'));
    await loading;
    ${riverpod ? '' : 'expect(controller.state, isA<${c}Loading>());'}
  });
''' : ''}}
''',
    'test/features/$n/${n}_page_test.dart':
        '''${clean ? "import 'dart:async';\n\n" : ''}import 'package:material_ui/material_ui.dart' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
${riverpod ? "import 'package:flutter_riverpod/flutter_riverpod.dart' as state_management;" : ''}
import '$prefix/${n}_route.dart';
import '$prefix/presentation/${n}_${style.name}.dart';
${riverpod ? '''final class _Observer extends state_management.ProviderObserver {
  bool disposed = false;

  @override
  void didDisposeProvider(state_management.ProviderObserverContext context) {
    if (context.provider == ${member}Provider) disposed = true;
  }
}
''' : ''}
${clean ? '''import '$prefix/data/datasources/${n}_datasource.dart';
import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/data/models/${n}_model.dart';
import '$prefix/data/repositories/${n}_repository_impl.dart';
import '$prefix/domain/usecases/load_$n.dart';

final class _Datasource implements ${c}Datasource {
  Future<${c}Model> Function() response = () async => throw const ${c}DataException('Offline');
  @override
  Future<${c}Model> load() => response();
}
''' : ''}
void main() {
  testWidgets('route ${clean ? 'loads, displays failure, retries and disposes' : 'owns and updates its notifier'}', (tester) async {
    ${clean ? 'final datasource = _Datasource();' : ''}
    var creations = 0;
    ${clean || !riverpod ? 'late $controller owned;' : ''}
    ${riverpod ? 'final observer = _Observer();' : ''}
    final router = GoRouter(
      initialLocation: '${location.value}',
      routes: [
        GoRoute(path: '$exitLocation', builder: (_, _) => const ui.SizedBox.shrink()),
        ${member}Route(create$controller: () {
        creations++;
        return ${clean || !riverpod ? 'owned = ' : ''}$create;
      })],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(${riverpod ? 'state_management.ProviderScope(observers: [observer], child: ui.MaterialApp.router(routerConfig: router))' : 'ui.MaterialApp.router(routerConfig: router)'});
    await tester.pumpAndSettle();
    expect(creations, 1);
    ${riverpod ? 'expect(observer.disposed, isFalse);' : 'var notifications = 0;\n    owned.addListener(() { notifications++; });'}
    ${clean ? '''expect(find.text('Offline'), findsOneWidget);
    datasource.response = () async => const ${c}Model(id: '2', title: 'Retried');
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retried'), findsOneWidget);
    final pending = Completer<${c}Model>();
    datasource.response = () => pending.future;
    final loading = owned.load();
    await tester.pump();
    expect(find.byType(ui.CircularProgressIndicator), findsOneWidget);''' : '''expect(find.text('Count: 0'), findsOneWidget);
    await tester.tap(find.byTooltip('Increment'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);'''}
    router.go('$exitLocation');
    await tester.pumpAndSettle();
    ${riverpod ? 'expect(observer.disposed, isTrue);' : 'expect(() => owned.addListener(() {}), throwsFlutterError);\n    final notificationsAtDisposal = notifications;'}
    ${clean ? "pending.complete(const ${c}Model(id: '3', title: 'Late'));" : ''}
    await tester.pumpAndSettle();
    ${clean ? 'await loading;' : ''}
    ${riverpod ? '' : 'expect(notifications, notificationsAtDisposal);'}
    expect(tester.takeException(), isNull);
    router.go('${location.value}');
    await tester.pumpAndSettle();
    expect(creations, 2);
    ${clean ? "expect(find.text('Late'), findsOneWidget);" : "expect(find.text('Count: 0'), findsOneWidget);"}
    await tester.pumpWidget(const ui.SizedBox.shrink());
  });
}
''',
  };
}
