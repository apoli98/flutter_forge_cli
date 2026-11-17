import '../project/names.dart';
import 'feature_templates.dart';

Map<String, String> cleanFeatureTests(
  DartName package,
  DartName name,
  StateStyle style,
) {
  final n = name.value;
  final c = name.className;
  final prefix = 'package:${package.value}/features/$n';
  final controller = '$c${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}';
  final invoke = style == StateStyle.cubit
      ? 'unawaited(controller.load());'
      : 'controller.add(const ${c}Requested());';
  return {
    'test/features/$n/${n}_test.dart':
        '''import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import '$prefix/data/datasources/${n}_datasource.dart';
import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/data/models/${n}_model.dart';
import '$prefix/data/repositories/${n}_repository_impl.dart';
import '$prefix/domain/usecases/load_$n.dart';
import '$prefix/presentation/${n}_${style.name}.dart';
${style == StateStyle.bloc ? "import '$prefix/presentation/${n}_event.dart';\n" : ''}import '$prefix/presentation/${n}_state.dart';

final class _Datasource implements ${c}Datasource {
  Future<${c}Model> Function() response = () async => const ${c}Model(id: '1', title: 'Starter');

  @override
  Future<${c}Model> load() => response();
}

void main() {
  blocTest<$controller, ${c}State>(
    'emits loading and loaded with fake-backed content',
    build: () => $controller(Load$c(${c}RepositoryImpl(_Datasource()))),
    act: (controller) { $invoke },
    expect: () => [isA<${c}Loading>(), isA<${c}Loaded>()],
  );

  test('starter mapping validates the explicit payload', () {
    final item = ${c}Model.fromJson({'id': '1', 'title': 'Starter'}).toEntity();
    expect(item.id, '1');
    expect(item.title, 'Starter');
    expect(() => ${c}Model.fromJson({'id': 1}), throwsA(isA<${c}DataException>()));
  });

  test('known data failures are typed; programming bugs propagate', () async {
    final datasource = _Datasource();
    final repository = ${c}RepositoryImpl(datasource);
    datasource.response = () async => throw const ${c}DataException('Offline');
    final failure = await repository.load();
    expect(failure.fold((error) => error.message, (_) => 'unexpected'), 'Offline');
    datasource.response = () async => throw StateError('bug');
    await expectLater(repository.load(), throwsStateError);
  });

  test('loads, fails and retries through the constructor chain', () async {
    final datasource = _Datasource();
    final controller = $controller(Load$c(${c}RepositoryImpl(datasource)));
    expect(controller.state, isA<${c}Loading>());
    final loaded = controller.stream.firstWhere((state) => state is ${c}Loaded);
    $invoke
    expect((await loaded as ${c}Loaded).item.title, 'Starter');
    datasource.response = () async => throw const ${c}DataException('Offline');
    final failed = controller.stream.firstWhere((state) => state is ${c}Failed);
    $invoke
    expect((await failed as ${c}Failed).failure.message, 'Offline');
    datasource.response = () async => const ${c}Model(id: '2', title: 'Retried');
    final retried = controller.stream.firstWhere((state) => state is ${c}Loaded);
    $invoke
    expect((await retried as ${c}Loaded).item.title, 'Retried');
    await controller.close();
  });

  test('pending load cannot emit after disposal', () async {
    final response = Completer<${c}Model>();
    final started = Completer<void>();
    final datasource = _Datasource()..response = () {
      started.complete();
      return response.future;
    };
    final controller = $controller(Load$c(${c}RepositoryImpl(datasource)))${style == StateStyle.bloc ? '..add(const ${c}Requested())' : ''};
    ${style == StateStyle.cubit ? invoke : ''}
    await started.future;
    final closing = controller.close();
    response.complete(const ${c}Model(id: '1', title: 'Late'));
    await closing;
    await Future<void>.delayed(Duration.zero);
    expect(controller.isClosed, isTrue);
    expect(controller.state, isA<${c}Loading>());
  });

  test('latest request wins when responses arrive out of order', () async {
    final first = Completer<${c}Model>();
    final second = Completer<${c}Model>();
    final bothStarted = Completer<void>();
    var calls = 0;
    final datasource = _Datasource()..response = () {
      calls++;
      if (calls == 1) return first.future;
      bothStarted.complete();
      return second.future;
    };
    final controller = $controller(Load$c(${c}RepositoryImpl(datasource)))${style == StateStyle.bloc ? '..add(const ${c}Requested())..add(const ${c}Requested())' : ''};
    ${style == StateStyle.cubit ? '$invoke\n    $invoke' : ''}
    await bothStarted.future;
    final loaded = controller.stream.firstWhere((state) => state is ${c}Loaded);
    second.complete(const ${c}Model(id: '2', title: 'Latest'));
    await loaded;
    first.complete(const ${c}Model(id: '1', title: 'Stale'));
    await Future<void>.delayed(Duration.zero);
    expect((controller.state as ${c}Loaded).item.title, 'Latest');
    await controller.close();
  });
}
''',
    'test/features/$n/${n}_page_test.dart':
        '''import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '$prefix/data/datasources/${n}_datasource.dart';
import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/data/models/${n}_model.dart';
import '$prefix/data/repositories/${n}_repository_impl.dart';
import '$prefix/domain/usecases/load_$n.dart';
import '$prefix/${n}_route.dart';
import '$prefix/presentation/${n}_${style.name}.dart';
import 'package:material_ui/material_ui.dart';

final class _Datasource implements ${c}Datasource {
  bool offline = true;

  @override
  Future<${c}Model> load() async {
    if (offline) throw const ${c}DataException('Offline');
    return const ${c}Model(id: '1', title: 'Loaded content');
  }
}

void main() {
  testWidgets('route loads, displays failure, retries and disposes', (tester) async {
    final datasource = _Datasource();
    late $controller controller;
    final route = ${name.memberName}Route(create$controller: () {
      return controller = $controller(Load$c(${c}RepositoryImpl(datasource)));
    });
    final router = GoRouter(initialLocation: route.path, routes: [route]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    datasource.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded content'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(controller.isClosed, isTrue);
    router.dispose();
  });
}
''',
  };
}
