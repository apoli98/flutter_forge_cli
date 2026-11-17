import '../project/names.dart';

Map<String, String> infrastructureFiles(DartName package) {
  final prefix = 'package:${package.value}';
  return {
    'tool/fix_localization_imports.dart': '''import 'dart:io';

/// Bridge Flutter 3.50 gen-l10n's legacy imports to standalone UI packages.
/// Run after gen-l10n; no diagnostics are disabled and no messages are changed.
void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  final file = File.fromUri(root.uri.resolve('lib/l10n/app_localizations.dart'));
  for (final relative in ['lib', 'lib/l10n', 'lib/l10n/app_localizations.dart']) {
    final current = root.uri.resolve(relative).toFilePath();
    if (FileSystemEntity.typeSync(current, followLinks: false) == FileSystemEntityType.link) {
      throw FileSystemException('Refusing a symbolic link', current);
    }
  }
  final source = file.readAsStringSync();
  const original = "import 'package:flutter_localizations/flutter_localizations.dart';";
  const replacement = "import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;\\n"
      "import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;\\n"
      "import 'package:cupertino_ui/cupertino_ui.dart' show GlobalCupertinoLocalizations;";
  if (source.contains(replacement)) return;
  if (!source.contains(original) || !source.contains('abstract class AppLocalizations')) {
    throw StateError('Unexpected gen-l10n output. Inspect before adapting the import bridge.');
  }
  file.writeAsStringSync(source.replaceFirst(original, replacement));
}
''',
    'assets/images/.gitkeep': '',
    'assets/icons/.gitkeep': '',
    'l10n.yaml': '''arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
''',
    'lib/l10n/app_en.arb':
        '''{
  "@@locale": "en",
  "appTitle": "${package.className}",
  "starterGreeting": "Welcome to your app"
}
''',
    'build.yaml': '''targets:
  \$default:
    builders:
      freezed:
        generate_for:
          - lib/features/**.dart
      json_serializable:
        generate_for:
          - lib/features/**.dart
        options:
          checked: true
          explicit_to_json: true
      source_gen:combining_builder:
        generate_for:
          - lib/features/**.dart
''',
    'lib/core/network/api_config.dart': '''/// Configure at the app composition root or with --dart-define=API_BASE_URL.
final class ApiConfig {
  const ApiConfig({
    this.baseUrl = const String.fromEnvironment('API_BASE_URL'),
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
  });

  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
}
''',
    'lib/core/network/api_exception.dart': '''import 'package:dio/dio.dart';

enum ApiErrorKind { notConfigured, timeout, connection, cancelled, certificate, unauthorized, forbidden, notFound, conflict, validation, server, response, unexpected }

/// Safe typed transport failure. Never retains URLs, headers or response bodies.
final class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout || DioExceptionType.transformTimeout => const ApiException(ApiErrorKind.timeout, 'The request timed out.'),
      DioExceptionType.connectionError => const ApiException(ApiErrorKind.connection, 'Unable to connect.'),
      DioExceptionType.cancel => const ApiException(ApiErrorKind.cancelled, 'The request was cancelled.'),
      DioExceptionType.badCertificate => const ApiException(ApiErrorKind.certificate, 'The secure connection could not be verified.'),
      DioExceptionType.badResponse => ApiException(switch (status) {
        401 => ApiErrorKind.unauthorized,
        403 => ApiErrorKind.forbidden,
        404 => ApiErrorKind.notFound,
        409 => ApiErrorKind.conflict,
        400 || 422 => ApiErrorKind.validation,
        final int code when code >= 500 => ApiErrorKind.server,
        _ => ApiErrorKind.response,
      }, 'The server could not complete the request.', statusCode: status),
      DioExceptionType.unknown => const ApiException(ApiErrorKind.unexpected, 'The request could not be completed.'),
    };
  }

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException(\$kind, statusCode: \$statusCode)';
}
''',
    'lib/core/network/api_client.dart':
        '''import 'package:dio/dio.dart';
import '$prefix/core/network/api_config.dart';
import '$prefix/core/network/api_exception.dart';

/// Transport only: features supply their real endpoint and typed JSON mapping.
final class ApiClient {
  ApiClient(this._dio);

  static Dio createDio(ApiConfig config) => Dio(BaseOptions(
    baseUrl: config.baseUrl,
    connectTimeout: config.connectTimeout,
    receiveTimeout: config.receiveTimeout,
    sendTimeout: config.sendTimeout,
    headers: {'Accept': 'application/json'},
  ));

  final Dio _dio;

  Future<Response<T>> request<T>(String path, {Options? options, Object? data, Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async {
    if (_dio.options.baseUrl.isEmpty) {
      throw const ApiException(ApiErrorKind.notConfigured, 'Configure API_BASE_URL before making API requests.');
    }
    try {
      return await _dio.request<T>(path, options: options, data: data, queryParameters: queryParameters, cancelToken: cancelToken);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
''',
    'test/core/network/api_client_test.dart':
        '''import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import '$prefix/core/network/api_client.dart';
import '$prefix/core/network/api_config.dart';
import '$prefix/core/network/api_exception.dart';

void main() {
  test('configuration applies timeouts and does not install logging', () {
    final dio = ApiClient.createDio(const ApiConfig());
    expect(dio.options.baseUrl, isEmpty);
    expect(dio.options.connectTimeout, const Duration(seconds: 15));
    expect(dio.options.receiveTimeout, const Duration(seconds: 30));
    expect(dio.interceptors.whereType<LogInterceptor>(), isEmpty);
    dio.close();
  });

  test('unconfigured client fails before a request', () async {
    final dio = ApiClient.createDio(const ApiConfig());
    await expectLater(ApiClient(dio).request<Object?>('/unused'), throwsA(isA<ApiException>().having((error) => error.kind, 'kind', ApiErrorKind.notConfigured)));
    dio.close();
  });

  test('Dio failures from the transport reach callers as typed safe errors', () async {
    final dio = ApiClient.createDio(const ApiConfig(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.reject(DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'private server details'));
    }));
    await expectLater(ApiClient(dio).request<Object?>('/supplied-by-test'), throwsA(isA<ApiException>().having((error) => error.kind, 'kind', ApiErrorKind.connection).having((error) => error.message, 'message', isNot(contains('private')))));
    dio.close();
  });

  test('transport and status errors map without exposing server secrets', () {
    for (final entry in {
      DioExceptionType.connectionTimeout: ApiErrorKind.timeout,
      DioExceptionType.sendTimeout: ApiErrorKind.timeout,
      DioExceptionType.receiveTimeout: ApiErrorKind.timeout,
      DioExceptionType.transformTimeout: ApiErrorKind.timeout,
      DioExceptionType.connectionError: ApiErrorKind.connection,
      DioExceptionType.cancel: ApiErrorKind.cancelled,
      DioExceptionType.badCertificate: ApiErrorKind.certificate,
      DioExceptionType.unknown: ApiErrorKind.unexpected,
    }.entries) {
      final error = ApiException.fromDio(DioException(requestOptions: RequestOptions(), type: entry.key, message: 'secret'));
      expect(error.kind, entry.value);
      expect(error.toString(), isNot(contains('secret')));
    }
    for (final entry in {400: ApiErrorKind.validation, 401: ApiErrorKind.unauthorized, 403: ApiErrorKind.forbidden, 404: ApiErrorKind.notFound, 409: ApiErrorKind.conflict, 422: ApiErrorKind.validation, 503: ApiErrorKind.server, 418: ApiErrorKind.response}.entries) {
      final request = RequestOptions();
      final error = ApiException.fromDio(DioException(requestOptions: request, type: DioExceptionType.badResponse, response: Response<Object?>(requestOptions: request, statusCode: entry.key, data: 'secret')));
      expect(error.kind, entry.value);
      expect(error.statusCode, entry.key);
      expect(error.message, isNot(contains('secret')));
    }
  });
}
''',
  };
}
