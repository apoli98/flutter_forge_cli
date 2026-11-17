import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/route_path.dart';
import 'clean_feature_test_templates.dart';
import 'feature_templates.dart';
import 'template_format.dart';

GenerationPlan cleanFeaturePlan(
  DartName package,
  DartName name,
  StateStyle style,
  RoutePath location,
) {
  final n = name.value;
  final base = 'lib/features/$n';
  return GenerationPlan(
    formatTemplates({
      ...cleanDomainFiles(package, name),
      '$base/presentation/${n}_state.dart': cleanStateFile(package, name),
      ..._cleanBlocFiles(package, name, style, location),
    }),
    absentDirectories: ['lib/features/$n', 'test/features/$n'],
  );
}

String cleanStateFile(DartName package, DartName name) {
  final n = name.value;
  final c = name.className;
  final prefix = 'package:${package.value}/features/$n';
  return '''import '$prefix/domain/entities/$n.dart';
import '$prefix/domain/${n}_failure.dart';

sealed class ${c}State {
  const ${c}State();
}

final class ${c}Loading extends ${c}State {
  const ${c}Loading();
}

final class ${c}Loaded extends ${c}State {
  const ${c}Loaded(this.item);

  final $c item;
}

final class ${c}Failed extends ${c}State {
  const ${c}Failed(this.failure);

  final ${c}Failure failure;
}
''';
}

Map<String, String> cleanDomainFiles(DartName package, DartName name) {
  final n = name.value;
  final c = name.className;
  final prefix = 'package:${package.value}/features/$n';
  final base = 'lib/features/$n';
  return {
    '$base/domain/entities/$n.dart':
        '''/// Starter contract, not an inferred API schema. Adapt id/title to your domain.
final class $c {
  const $c({required this.id, required this.title});

  final String id;
  final String title;
}
''',
    '$base/domain/${n}_failure.dart':
        '''/// An expected data-source failure safe to display to a user.
final class ${c}Failure {
  const ${c}Failure(this.message);

  final String message;
}
''',
    '$base/domain/repositories/${n}_repository.dart':
        '''import 'package:fpdart/fpdart.dart' as functional;
import '$prefix/domain/entities/$n.dart';
import '$prefix/domain/${n}_failure.dart';

abstract interface class ${c}Repository {
  Future<functional.Either<${c}Failure, $c>> load();
}
''',
    '$base/domain/usecases/load_$n.dart':
        '''import 'package:fpdart/fpdart.dart' as functional;
import '$prefix/domain/entities/$n.dart';
import '$prefix/domain/repositories/${n}_repository.dart';
import '$prefix/domain/${n}_failure.dart';

final class Load$c {
  const Load$c(this._repository);

  final ${c}Repository _repository;

  Future<functional.Either<${c}Failure, $c>> call() => _repository.load();
}
''',
    '$base/data/datasources/${n}_exception.dart':
        '''/// Throw only for expected adapter failures; programming bugs must propagate.
final class ${c}DataException implements Exception {
  const ${c}DataException(this.message);

  final String message;
}
''',
    '$base/data/datasources/${n}_datasource.dart':
        '''import '$prefix/data/models/${n}_model.dart';

/// Supply an explicit local or remote adapter at the app composition root.
/// Translate known transport failures to ${c}DataException in that adapter.
abstract interface class ${c}Datasource {
  Future<${c}Model> load();
}
''',
    '$base/data/models/${n}_model.dart':
        '''import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/domain/entities/$n.dart';

/// Explicit starter payload: nonempty string id and title. Adapt before API use.
final class ${c}Model {
  const ${c}Model({required this.id, required this.title});

  factory ${c}Model.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      throw const ${c}DataException('Invalid $c starter payload.');
    }
    return ${c}Model(id: id, title: title);
  }

  final String id;
  final String title;

  $c toEntity() => $c(id: id, title: title);
}
''',
    '$base/data/repositories/${n}_repository_impl.dart':
        '''import 'package:fpdart/fpdart.dart' as functional;
import '$prefix/data/datasources/${n}_datasource.dart';
import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/domain/entities/$n.dart';
import '$prefix/domain/repositories/${n}_repository.dart';
import '$prefix/domain/${n}_failure.dart';

final class ${c}RepositoryImpl implements ${c}Repository {
  const ${c}RepositoryImpl(this._datasource);

  final ${c}Datasource _datasource;

  @override
  Future<functional.Either<${c}Failure, $c>> load() async {
    try {
      return functional.Right((await _datasource.load()).toEntity());
    } on ${c}DataException catch (error) {
      return functional.Left(${c}Failure(error.message));
    }
  }
}
''',
  };
}

Map<String, String> _cleanBlocFiles(
  DartName package,
  DartName name,
  StateStyle style,
  RoutePath location,
) {
  final n = name.value;
  final c = name.className;
  final prefix = 'package:${package.value}/features/$n';
  final base = 'lib/features/$n';
  final controller = '$c${style == StateStyle.cubit ? 'Cubit' : 'Bloc'}';
  final request = style == StateStyle.cubit
      ? 'unawaited(context.read<$controller>().load());'
      : 'context.read<$controller>().add(const ${c}Requested());';
  return {
    if (style == StateStyle.cubit)
      '$base/presentation/${n}_cubit.dart':
          '''import 'package:flutter_bloc/flutter_bloc.dart';
import '$prefix/domain/usecases/load_$n.dart';
import '$prefix/presentation/${n}_state.dart';

final class $controller extends Cubit<${c}State> {
  $controller(this._load) : super(const ${c}Loading());

  final Load$c _load;
  int _request = 0;

  Future<void> load() async {
    if (isClosed) return;
    final request = ++_request;
    emit(const ${c}Loading());
    final result = await _load();
    if (isClosed || request != _request) return;
    emit(result.fold(${c}Failed.new, ${c}Loaded.new));
  }
}
'''
    else ...{
      '$base/presentation/${n}_event.dart':
          '''sealed class ${c}Event {
  const ${c}Event();
}

final class ${c}Requested extends ${c}Event {
  const ${c}Requested();
}
''',
      '$base/presentation/${n}_bloc.dart':
          '''import 'package:flutter_bloc/flutter_bloc.dart';
import '$prefix/domain/usecases/load_$n.dart';
import '$prefix/presentation/${n}_event.dart';
import '$prefix/presentation/${n}_state.dart';

final class $controller extends Bloc<${c}Event, ${c}State> {
  $controller(Load$c load) : super(const ${c}Loading()) {
    on<${c}Requested>((event, emit) async {
      final request = ++_request;
      emit(const ${c}Loading());
      final result = await load();
      if (emit.isDone || isClosed || request != _request) return;
      emit(result.fold(${c}Failed.new, ${c}Loaded.new));
    });
  }

  int _request = 0;
}
''',
    },
    '$base/${n}_route.dart':
        '''${style == StateStyle.cubit ? "import 'dart:async';\n\n" : ''}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '$prefix/presentation/${n}_${style.name}.dart';
${style == StateStyle.bloc ? "import '$prefix/presentation/${n}_event.dart';\n" : ''}import '$prefix/presentation/${n}_page.dart';

GoRoute ${name.memberName}Route({required $controller Function() create$controller}) => GoRoute(
  path: '${location.value}',
  builder: (context, state) => BlocProvider(
    create: (_) {
      ${style == StateStyle.cubit ? 'final controller = create$controller();\n      unawaited(controller.load());\n      return controller;' : 'return create$controller()..add(const ${c}Requested());'}
    },
    child: const ${c}Page(),
  ),
);
''',
    '$base/presentation/${n}_page.dart':
        '''${style == StateStyle.cubit ? "import 'dart:async';\n\n" : ''}import 'package:flutter_bloc/flutter_bloc.dart';
import '$prefix/presentation/${n}_${style.name}.dart';
${style == StateStyle.bloc ? "import '$prefix/presentation/${n}_event.dart';\n" : ''}import '$prefix/presentation/${n}_state.dart';
import 'package:material_ui/material_ui.dart';

class ${c}Page extends StatelessWidget {
  const ${c}Page({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('$c')),
    body: Center(
      child: BlocBuilder<$controller, ${c}State>(
        builder: (context, state) => switch (state) {
          ${c}Loading() => const CircularProgressIndicator(),
          ${c}Loaded(:final item) => Text(item.title),
          ${c}Failed(:final failure) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(failure.message),
              TextButton(
                onPressed: () { $request },
                child: const Text('Retry'),
              ),
            ],
          ),
        },
      ),
    ),
  );
}
''',
    ...cleanFeatureTests(package, name, style),
  };
}
