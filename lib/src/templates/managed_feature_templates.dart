import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/profiles.dart';
import 'feature_artifact.dart';
import 'feature_templates.dart';
import 'template_format.dart';

FeatureArtifact managedFeatureArtifact(
  DartName package,
  DartName name, {
  required StateStyle style,
  required Recipe recipe,
  required String routePath,
}) {
  final artifact = featureArtifact(
    package,
    name,
    style: style,
    recipe: recipe,
    routePath: routePath,
  );
  final files = Map<String, String>.of(artifact.plan.files);
  final n = name.value;
  final c = name.className;
  final base = 'lib/features/$n';
  final prefix = 'package:${package.value}/features/$n';
  // Model generation uses an explicit annotation because its fromJson boundary
  // catches checked decoding failures instead of using an expression body.
  if (recipe == Recipe.clean) {
    final testPath = 'test/features/$n/${n}_test.dart';
    final modelTest =
        '''
  test('generated JSON round trips and rejects malformed starter fields', () {
    const model = ${c}Model(id: '1', title: 'Starter');
    expect(${c}Model.fromJson(model.toJson()), model);
    for (final json in <Map<String, dynamic>>[
      {'id': '', 'title': 'Starter'},
      {'id': '1', 'title': ''},
      {'id': '1'},
      {'id': 1, 'title': 'Starter'},
    ]) {
      expect(() => ${c}Model.fromJson(json), throwsA(isA<${c}DataException>()));
    }
  });
''';
    files[testPath] = files[testPath]!.replaceFirst(
      'void main() {',
      'void main() {\n$modelTest',
    );
    files['$base/data/models/${n}_model.dart'] =
        '''import 'package:freezed_annotation/freezed_annotation.dart';
import '$prefix/data/datasources/${n}_exception.dart';
import '$prefix/domain/entities/$n.dart' as domain;

part '${n}_model.freezed.dart';
part '${n}_model.g.dart';

/// Explicit local starter schema, not an inferred remote API contract.
@Freezed(fromJson: true, toJson: true)
abstract class ${c}Model with _\$${c}Model {
  const factory ({
    @_NonemptyStringConverter() required String id,
    @_NonemptyStringConverter() required String title,
  }) = _${c}Model;

  const new _();

  factory ${c}Model.fromJson(Map<String, dynamic> json) {
    try {
      return _\$${c}ModelFromJson(json);
    } on CheckedFromJsonException {
      throw const ${c}DataException('Invalid $c starter payload.');
    }
  }

  domain.$c toEntity() => domain.$c(id: id, title: title);
}

final class _NonemptyStringConverter implements JsonConverter<String, Object?> {
  const new();

  @override
  String fromJson(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('Expected a nonempty string.');
    }
    return value;
  }

  @override
  String toJson(String value) => value;
}
''';
    files['$base/presentation/${n}_state.dart'] =
        '''import 'package:freezed_annotation/freezed_annotation.dart';
import '$prefix/domain/entities/$n.dart' as domain;
import '$prefix/domain/${n}_failure.dart';

part '${n}_state.freezed.dart';

@freezed
sealed class ${c}State with _\$${c}State {
  const factory loading() = ${c}Loading;
  const factory loaded(domain.$c item) = ${c}Loaded;
  const factory failed(${c}Failure failure) = ${c}Failed;
}
''';
    files['$base/data/datasources/local_${n}_datasource.dart'] =
        '''import '$prefix/data/datasources/${n}_datasource.dart';
import '$prefix/data/models/${n}_model.dart';

/// Explicit local starter content. Replace this adapter at the app composition root.
final class Local${c}Datasource implements ${c}Datasource {
  const Local${c}Datasource();

  @override
  Future<${c}Model> load() async => const ${c}Model(id: '$n', title: '${n == 'home' ? 'Welcome to your app' : '$c local starter'}');
}
''';
  } else if (style.usesBloc) {
    files['$base/presentation/${n}_state.dart'] =
        '''import 'package:freezed_annotation/freezed_annotation.dart';

part '${n}_state.freezed.dart';

@freezed
abstract class ${c}State with _\$${c}State {
  const factory ({@Default(0) int count}) = _${c}State;
}
''';
  }
  if (style == StateStyle.bloc) {
    files['$base/presentation/${n}_event.dart'] =
        '''import 'package:freezed_annotation/freezed_annotation.dart';

part '${n}_event.freezed.dart';

@freezed
sealed class ${c}Event with _\$${c}Event {
  const factory ${recipe == Recipe.clean ? 'requested' : 'incrementPressed'}() = $c${recipe == Recipe.clean ? 'Requested' : 'IncrementPressed'};
}
''';
  }
  return FeatureArtifact(
    plan: GenerationPlan(
      formatTemplates(files),
      absentDirectories: artifact.plan.absentDirectories,
    ),
    wiring: artifact.wiring,
  );
}
