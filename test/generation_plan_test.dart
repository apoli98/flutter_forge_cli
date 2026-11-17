import 'dart:io';

import 'package:flutter_forge_cli/src/generation/generation_plan.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory temp;
  final writer = FileWriter();
  setUp(() => temp = temporaryDirectory());
  tearDown(() => temp.deleteSync(recursive: true));

  test('rejects traversal and file-parent conflicts at plan construction', () {
    for (final path in [
      '',
      '/tmp/a',
      '../a',
      'a/../b',
      './a',
      'a//b',
      'a/',
      r'a\b',
      'C:/a',
    ]) {
      expect(() => GenerationPlan({path: ''}), throwsFormatException);
      expect(
        () => GenerationPlan({}, absentDirectories: [path]),
        throwsFormatException,
      );
    }
    expect(() => GenerationPlan({'a': '', 'a/b': ''}), throwsFormatException);
  });

  test('preflights every collision before writing anything', () {
    writeFile(temp.path, 'existing', 'keep');
    final before = snapshot(temp.path);
    expect(
      () => writer.write(
        temp.path,
        GenerationPlan({'new/file': 'new', 'existing': 'replace'}),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(snapshot(temp.path), before);
  });

  test('rejects files used as parents and existing feature directories', () {
    writeFile(temp.path, 'parent', 'keep');
    expect(
      () => writer.check(temp.path, GenerationPlan({'parent/child': ''})),
      throwsA(isA<FileSystemException>()),
    );
    Directory(p.join(temp.path, 'lib/features/orders'))
        .createSync(recursive: true);
    expect(
      () => writer.write(
        temp.path,
        GenerationPlan(
          {'other': ''},
          absentDirectories: ['lib/features/orders'],
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(p.join(temp.path, 'other')).existsSync(), isFalse);
  });

  test('writes new files and refuses a repeated write', () {
    final root = p.join(temp.path, 'new_root');
    final plan = GenerationPlan({'a/b.dart': 'hello', 'c': 'world'});
    writer.write(root, plan);
    expect(snapshot(root), {'a/b.dart': 'hello', 'c': 'world'});
    expect(() => writer.write(root, plan), throwsA(isA<FileSystemException>()));
  });

  test('managed replacements compare every expected file before any write', () {
    writeFile(temp.path, 'owned.dart', 'generated');
    writeFile(temp.path, 'other.dart', 'edited');
    final before = snapshot(temp.path);
    final plan = GenerationPlan({
      'new.dart': 'new',
      'owned.dart': 'next',
      'other.dart': 'next',
    });
    expect(
      () => writer.writeManaged(temp.path, plan, {
        'owned.dart': 'generated',
        'other.dart': 'generated',
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(snapshot(temp.path), before);
    writer.writeManaged(temp.path, plan, {
      'owned.dart': 'generated',
      'other.dart': 'edited',
    });
    expect(snapshot(temp.path), {
      'new.dart': 'new',
      'owned.dart': 'next',
      'other.dart': 'next',
    });
    expect(
      () => writer.checkManaged(temp.path, GenerationPlan({}), {
        'outside.dart': 'x',
      }),
      throwsArgumentError,
    );
  });

  test('fresh overlay is limited and preflights unknown collisions', () {
    writeFile(temp.path, 'lib/main.dart', 'stock');
    writeFile(temp.path, 'lib/app/router.dart', 'keep');
    final before = snapshot(temp.path);
    expect(
      () => writer.writeFreshApp(
        temp.path,
        GenerationPlan({'lib/main.dart': 'new', 'lib/app/router.dart': 'new'}),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(snapshot(temp.path), before);
    writer.writeFreshApp(temp.path, GenerationPlan({'lib/main.dart': 'new'}));
    expect(File(p.join(temp.path, 'lib/main.dart')).readAsStringSync(), 'new');
  });

  test(
    'allows selected root aliases but rejects in-tree and dangling links',
    () {
      if (Platform.isWindows) return;
      final real = Directory(p.join(temp.path, 'real'))..createSync();
      final alias = Link(p.join(temp.path, 'alias'))..createSync(real.path);
      writer.write(alias.path, GenerationPlan({'safe': 'ok'}));
      expect(File(p.join(real.path, 'safe')).readAsStringSync(), 'ok');
      Link(p.join(real.path, 'escape')).createSync(temp.path);
      Link(p.join(real.path, 'dangling'))
          .createSync(p.join(temp.path, 'missing'));
      for (final path in ['escape/out', 'dangling/out', 'escape']) {
        expect(
          () => writer.write(real.path, GenerationPlan({path: 'unsafe'})),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(File(p.join(temp.path, 'out')).existsSync(), isFalse);
      expect(
        () => writer.writeFreshApp(
          real.path,
          GenerationPlan({'escape': 'unsafe'}),
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
