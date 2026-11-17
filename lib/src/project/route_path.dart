/// A static GoRouter location safe to embed in generated Dart source.
final class RoutePath {
  RoutePath.parse(this.value) {
    if (value != '/' &&
        !RegExp(r'^/[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_-]+)*$').hasMatch(value)) {
      throw const FormatException(
        'Route must be an absolute static path, such as /orders/history. '
        'Parameters, queries, fragments, escapes and trailing slashes are not supported.',
      );
    }
  }

  final String value;
}
