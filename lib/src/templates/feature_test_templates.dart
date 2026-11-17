import '../project/names.dart';
import 'feature_templates.dart';

Map<String, String> featureTests(
  DartName package,
  DartName name,
  StateStyle style,
) {
  final n = name.value;
  final c = name.className;
  final controller = '$c${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}';
  final kind = style.name;
  final prefix = 'package:${package.value}/features/$n';
  final action = style == StateStyle.cubit
      ? 'controller..increment()..increment();'
      : 'controller..add(const ${c}IncrementPressed())..add(const ${c}IncrementPressed());';
  return {
    'test/features/$n/${n}_${kind}_test.dart':
        '''import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import '$prefix/presentation/${n}_$kind.dart';
${style == StateStyle.bloc ? "import '$prefix/presentation/${n}_event.dart';\n" : ''}import '$prefix/presentation/${n}_state.dart';

void main() {
  test('starts from the injected count', () async {
    final controller = $controller(initialCount: 4);
    expect(controller.state, const ${c}State(count: 4));
    await controller.close();
  });

  blocTest<$controller, ${c}State>(
    'increments twice from the injected count',
    build: () => $controller(initialCount: 4),
    act: (controller) {
      $action
    },
    expect: () => const [${c}State(count: 5), ${c}State(count: 6)],
  );
}
''',
    'test/features/$n/${n}_page_test.dart':
        '''import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '$prefix/${n}_route.dart';
import '$prefix/presentation/${n}_$kind.dart';

void main() {
  testWidgets('route injects, updates, and closes its controller', (tester) async {
    late $controller controller;
    final route = ${name.memberName}Route(create$controller: () {
      return controller = $controller(initialCount: 4);
    });
    final router = GoRouter(initialLocation: route.path, routes: [route]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Count: 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Increment'));
    await tester.pumpAndSettle();
    expect(find.text('Count: 5'), findsOneWidget);
    expect(find.text('Count: 4'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(controller.isClosed, isTrue);
    router.dispose();
  });
}
''',
  };
}
