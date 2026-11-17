import '../project/managed_feature.dart';
import '../project/names.dart';
import '../project/profiles.dart';
import 'feature_artifact.dart';
import 'template_format.dart';

/// The only files feature generation may update, rendered from typed entries.
Map<String, String> managedIntegrationFiles(
  DartName package,
  List<ManagedFeature> features,
) {
  final prefix = 'package:${package.value}';
  final wirings = features
      .map(
        (feature) => FeatureWiring(
          package,
          feature.name,
          feature.state,
          feature.recipe,
          feature.route,
        ),
      )
      .toList();
  final imports = <String>{};
  for (final wiring in wirings) {
    imports.addAll(
      wiring.imports.where((line) => !line.contains('_route.dart')),
    );
    if (wiring.recipe == Recipe.clean) {
      final n = wiring.name.value;
      imports.add(
        "import '${wiring.prefix}/data/datasources/local_${n}_datasource.dart';",
      );
      imports.add(
        "import '${wiring.prefix}/domain/repositories/${n}_repository.dart';",
      );
    }
  }
  final featureImports = imports.toList()..sort();
  final aliases = <String, String>{
    for (var index = 0; index < featureImports.length; index++)
      RegExp(r"import '([^']+)';").firstMatch(featureImports[index])![1]!:
          'feature$index',
  };
  String qualified(FeatureWiring wiring, String path, String symbol) =>
      '${aliases['${wiring.prefix}/$path']!}.$symbol';
  String controller(FeatureWiring wiring) => qualified(
    wiring,
    'presentation/${wiring.name.value}_${wiring.style.name}.dart',
    wiring.controller,
  );
  String datasource(FeatureWiring wiring) => qualified(
    wiring,
    'data/datasources/${wiring.name.value}_datasource.dart',
    wiring.datasource,
  );
  String repository(FeatureWiring wiring) => qualified(
    wiring,
    'domain/repositories/${wiring.name.value}_repository.dart',
    '${wiring.name.className}Repository',
  );
  String load(FeatureWiring wiring) => qualified(
    wiring,
    'domain/usecases/load_${wiring.name.value}.dart',
    'Load${wiring.name.className}',
  );
  final routeImports =
      wirings
          .expand(
            (wiring) =>
                wiring.imports.where((line) => line.contains('_route.dart')),
          )
          .toSet()
          .toList()
        ..sort();
  return formatTemplates({
    'lib/app/dependencies.dart':
        '''// Forge-managed. Edits stop automatic registration.
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import '$prefix/core/network/api_client.dart';
import '$prefix/core/network/api_config.dart';
${aliases.entries.map((entry) => "import '${entry.key}' as ${entry.value};").join('\n')}

/// App-owned container. Features receive dependencies only via constructors.
GetIt createDependencies({ApiConfig apiConfig = const ApiConfig(), ${wirings.where((wiring) => wiring.recipe == Recipe.clean).map((wiring) => '${datasource(wiring)}? ${wiring.parameter},').join(' ')}}) {
  final services = GetIt.asNewInstance();
  services
    ..registerSingleton<ApiConfig>(apiConfig)
    ..registerLazySingleton<Dio>(() => ApiClient.createDio(services<ApiConfig>()), dispose: (dio) => dio.close(force: true))
    ..registerLazySingleton<ApiClient>(() => ApiClient(services<Dio>()))
${wirings.map((wiring) {
          final c = wiring.name.className;
          return wiring.recipe == Recipe.counter ? '    ..registerFactory<${controller(wiring)}>(${controller(wiring)}.new)' : '''    ..registerLazySingleton<${datasource(wiring)}>(() => ${wiring.parameter} ?? const ${qualified(wiring, 'data/datasources/local_${wiring.name.value}_datasource.dart', 'Local${c}Datasource')}())
    ..registerLazySingleton<${repository(wiring)}>(() => ${qualified(wiring, 'data/repositories/${wiring.name.value}_repository_impl.dart', '${c}RepositoryImpl')}(services<${datasource(wiring)}>()))
    ..registerLazySingleton<${load(wiring)}>(() => ${load(wiring)}(services<${repository(wiring)}>()))
    ..registerFactory<${controller(wiring)}>(() => ${controller(wiring)}(services<${load(wiring)}>()))''';
        }).join('\n')};
  return services;
}
''',
    'lib/app/router.dart':
        '''// Forge-managed. Edits stop automatic registration.
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
${routeImports.indexed.map((entry) => entry.$2.replaceFirst(';', ' as route${entry.$1};')).join('\n')}
${wirings.map((wiring) => "import '${wiring.prefix}/presentation/${wiring.name.value}_${wiring.style.name}.dart' as ${aliases['${wiring.prefix}/presentation/${wiring.name.value}_${wiring.style.name}.dart']};").join('\n')}

GoRouter createRouter(GetIt services) => GoRouter(
  routes: [
${wirings.map((wiring) => "    route${routeImports.indexOf("import '${wiring.prefix}/${wiring.name.value}_route.dart';")}.${wiring.name.memberName}Route(create${wiring.controller}: () => services.get<${controller(wiring)}>()),").join('\n')}
  ],
);
''',
  });
}
