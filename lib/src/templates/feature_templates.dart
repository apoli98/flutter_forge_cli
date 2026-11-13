import '../generation/generation_plan.dart';
import '../project/names.dart';
import 'feature_test_templates.dart';

enum StateStyle { cubit, bloc }

GenerationPlan featurePlan(
  DartName package,
  DartName name, {
  StateStyle style = StateStyle.cubit,
  String? routePath,
}) {
  final n = name.value;
  final c = name.className;
  final kind = style.name;
  final controller = '$c${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}';
  final base = 'lib/features/$n';
  final increment = style == StateStyle.cubit
      ? 'context.read<$controller>().increment()'
      : 'context.read<$controller>().add(const ${c}IncrementPressed())';
  return GenerationPlan(
    {
      '$base/${n}_route.dart':
          '''import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'presentation/${n}_$kind.dart';
import 'presentation/${n}_page.dart';

GoRoute ${name.memberName}Route({required $controller Function() create$controller}) => GoRoute(
  path: '${routePath ?? '/$n'}',
  builder: (context, state) => BlocProvider(
    create: (_) => create$controller(),
    child: const ${c}Page(),
  ),
);
''',
      '$base/presentation/${n}_state.dart':
          '''final class ${c}State {
  const ${c}State({this.count = 0});

  final int count;

  @override
  bool operator ==(Object other) => other is ${c}State && other.count == count;

  @override
  int get hashCode => count.hashCode;
}
''',
      if (style == StateStyle.cubit)
        '$base/presentation/${n}_cubit.dart':
            '''import 'package:flutter_bloc/flutter_bloc.dart';

import '${n}_state.dart';

final class ${c}Cubit extends Cubit<${c}State> {
  ${c}Cubit({int initialCount = 0}) : super(${c}State(count: initialCount));

  void increment() => emit(${c}State(count: state.count + 1));
}
'''
      else ...{
        '$base/presentation/${n}_event.dart':
            '''sealed class ${c}Event {
  const ${c}Event();
}

final class ${c}IncrementPressed extends ${c}Event {
  const ${c}IncrementPressed();
}
''',
        '$base/presentation/${n}_bloc.dart':
            '''import 'package:flutter_bloc/flutter_bloc.dart';

import '${n}_event.dart';
import '${n}_state.dart';

final class ${c}Bloc extends Bloc<${c}Event, ${c}State> {
  ${c}Bloc({int initialCount = 0}) : super(${c}State(count: initialCount)) {
    on<${c}IncrementPressed>((event, emit) {
      emit(${c}State(count: state.count + 1));
    });
  }
}
''',
      },
      '$base/presentation/${n}_page.dart':
          '''import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '${n}_$kind.dart';
${style == StateStyle.bloc ? "import '${n}_event.dart';\n" : ''}import '${n}_state.dart';

class ${c}Page extends StatelessWidget {
  const ${c}Page({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('$c')),
    body: Center(
      child: BlocBuilder<$controller, ${c}State>(
        builder: (context, state) => Text(
          'Count: \${state.count}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => $increment,
      tooltip: 'Increment',
      child: const Icon(Icons.add),
    ),
  );
}
''',
      ...featureTests(package, name, style),
    },
    absentDirectories: ['lib/features/$n', 'test/features/$n'],
  );
}

String featureWiring(DartName name, StateStyle style) {
  final n = name.value;
  final controller =
      '${name.className}${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}';
  return '''In lib/app/router.dart, add these imports:
import '../features/$n/${n}_route.dart';
import '../features/$n/presentation/${n}_${style.name}.dart';

In the GoRouter routes list, add:
${name.memberName}Route(create$controller: $controller.new),

Navigate to /$n (for example, context.go('/$n')).
The route's BlocProvider creates and closes its controller.
''';
}
