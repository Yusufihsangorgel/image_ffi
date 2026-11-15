/// Turns an app made by `flutter create` into the consumer the compat
/// workflow builds: copies the on-device thumbnail test and its fixture into
/// it and declares the fixture as an asset.
///
/// Usage: `dart tool/ci/prepare_app.dart <app directory>`
///
/// The dependency on image_ffi is added separately with `flutter pub add`.
library;

import 'dart:io';

/// The fixture `integration_test/thumbnail_test.dart` loads, under `assets/`.
const fixture = 'gradient_96x64.png';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart tool/ci/prepare_app.dart <app directory>');
    exit(64);
  }
  final app = Directory(args.single);
  final ci = File.fromUri(Platform.script).parent;

  _copy(
    File('${ci.path}/integration_test/thumbnail_test.dart'),
    File('${app.path}/integration_test/thumbnail_test.dart'),
  );
  _copy(
    File('${ci.path}/fixtures/$fixture'),
    File('${app.path}/assets/$fixture'),
  );

  // The generated pubspec has a top-level `flutter:` section with no asset
  // list. Inserting one right below the key keeps the rest of the template.
  final pubspec = File('${app.path}/pubspec.yaml');
  final lines = pubspec.readAsLinesSync();
  final section = lines.indexOf('flutter:');
  if (section < 0 || lines.any((line) => line.startsWith('  assets:'))) {
    stderr.writeln('unexpected pubspec layout in ${pubspec.path}');
    exit(1);
  }
  lines.insertAll(section + 1, ['  assets:', '    - assets/$fixture']);
  pubspec.writeAsStringSync('${lines.join('\n')}\n');
  print('prepared ${app.path}');
}

void _copy(File from, File to) {
  to.parent.createSync(recursive: true);
  from.copySync(to.path);
}
