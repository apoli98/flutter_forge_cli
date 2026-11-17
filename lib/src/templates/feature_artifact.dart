import '../generation/generation_plan.dart';
import '../project/names.dart';
import '../project/profiles.dart';
import '../project/route_path.dart';

/// The generated files and the one authoritative composition contract.
final class FeatureArtifact {
  FeatureArtifact({required this.plan, required this.wiring});

  final GenerationPlan plan;
  final FeatureWiring wiring;
}

final class FeatureWiring {
  FeatureWiring(
    DartName package,
    this.name,
    this.style,
    this.recipe,
    this.location,
  ) : prefix = 'package:${package.value}/features/${name.value}';

  final DartName name;
  final StateStyle style;
  final Recipe recipe;
  final RoutePath location;
  final String prefix;

  String get controller => '${name.className}${style.controllerSuffix}';
  String get datasource => '${name.className}Datasource';
  String get parameter => '${name.memberName}Datasource';

  List<String> get imports => [
    "import '$prefix/${name.value}_route.dart';",
    "import '$prefix/presentation/${name.value}_${style.name}.dart';",
    if (recipe == Recipe.clean) ...[
      "import '$prefix/data/datasources/${name.value}_datasource.dart';",
      "import '$prefix/data/repositories/${name.value}_repository_impl.dart';",
      "import '$prefix/domain/usecases/load_${name.value}.dart';",
    ],
  ]..sort();

  String get controllerExpression => recipe == Recipe.counter
      ? '$controller.new'
      : '() => $controller(Load${name.className}(${name.className}RepositoryImpl($parameter)))';

  String get routeEntry =>
      '${name.memberName}Route(create$controller: $controllerExpression),';

  Map<String, Object> toJson() => {
    'routerFile': 'lib/app/router.dart',
    'imports': imports,
    'routeEntry': routeEntry,
    'location': location.value,
    'controllerExpression': controllerExpression,
    if (recipe == Recipe.clean) ...{
      'requiredParameter': '$datasource $parameter',
      'datasourceContract':
          '$prefix/data/datasources/${name.value}_datasource.dart',
    },
    'text': text,
  };

  String get text =>
      '''In your router composition file (for example lib/app/router.dart), add:
${imports.join('\n')}

${recipe == Recipe.clean ? 'Implement $datasource.load() with your real adapter (or an explicitly named local data source).\nRequire $datasource $parameter in your router factory; pass that instance from the app composition root.\n' : ''}In the GoRouter routes list, add:
$routeEntry

Navigate to ${location.value} (for example, context.go('${location.value}')).
${switch (style) {
        StateStyle.cubit || StateStyle.bloc => "The route's BlocProvider creates and closes its controller.",
        StateStyle.riverpod => "The route's ProviderScope overrides the auto-disposed notifier provider and owns its lifecycle. No app-wide ProviderScope is required for this route.",
        StateStyle.provider => "The route's ChangeNotifierProvider creates and disposes its notifier.",
      }}
Check route uniqueness manually; existing routers were not inspected or changed.
${recipe == Recipe.clean ? 'Optional GetIt integration, in your composition root only:\ngetIt.registerLazySingleton<$datasource>(() => Your${name.className}Datasource());\nPass getIt<$datasource>() as $parameter to the router factory.\nYour${name.className}Datasource is your adapter implementation, not a generated class.\n' : ''}''';
}
