import 'package:flutter_forge_cli/src/project/names.dart';
import 'package:test/test.dart';

void main() {
  test('names expose Dart class and route factory identifiers', () {
    final name = DartName.parse('order_history');
    expect(name.className, 'OrderHistory');
    expect(name.memberName, 'orderHistory');
    expect(DartName.parse('a1').className, 'A1');
  });

  for (final pair in [
    (
      valid: 'order1',
      invalid: 'order_1',
      className: 'Order1',
      memberName: 'order1',
    ),
    (
      valid: 'http2_client',
      invalid: 'http_2_client',
      className: 'Http2Client',
      memberName: 'http2Client',
    ),
  ]) {
    test('accepts ${pair.valid} but rejects ambiguous ${pair.invalid}', () {
      final name = DartName.parse(pair.valid);
      expect(name.className, pair.className);
      expect(name.memberName, pair.memberName);
      expect(() => DartName.parse(pair.invalid), throwsFormatException);
    });
  }

  test('rejects unsafe, invalid and reserved names', () {
    for (final value in [
      '',
      '../escape',
      '/absolute',
      'hello-world',
      'CamelCase',
      '_private',
      '1name',
      'two__words',
      'trailing_',
      'class',
      'flutter',
      'dart',
      'with space',
      r'a\b',
      'a:b',
      '🔥',
    ]) {
      expect(() => DartName.parse(value), throwsFormatException, reason: value);
    }
  });

  test('validates organization and supported unique platforms', () {
    validateOrganization('com.example');
    validateOrganization('dev.example123.tools');
    for (final value in [
      '',
      'example',
      'com..app',
      'Com.example',
      'com.bad-org',
      'com.class',
    ]) {
      expect(() => validateOrganization(value), throwsFormatException);
    }
    expect(parsePlatforms('web,ios,android'), ['web', 'ios', 'android']);
    for (final value in ['', 'web,web', 'web, android', 'watchos', ',ios']) {
      expect(() => parsePlatforms(value), throwsFormatException);
    }
  });
}
