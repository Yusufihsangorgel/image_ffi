/// Checks that an app depending on image_ffi resolved the native-assets
/// packages to the versions expected for its Flutter release line.
///
/// Usage:
///
/// ```
/// flutter pub deps --json > deps.json
/// dart tool/ci/check_resolution.dart deps.json code_assets=1.2.1 hooks=2.0.2
/// ```
///
/// Prints the resolved version of every named package and exits with 1 if one
/// is missing or differs from its expected version.
library;

import 'dart:convert';
import 'dart:io';

/// The package under test. It has to resolve from the checkout.
const package = 'image_ffi';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart tool/ci/check_resolution.dart <deps.json> name=version...',
    );
    exit(64);
  }

  final expected = <String, String>{};
  for (final arg in args.skip(1)) {
    final parts = arg.split('=');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      stderr.writeln('expected name=version, got "$arg"');
      exit(64);
    }
    expected[parts[0]] = parts[1];
  }

  final resolved = _readVersions(File(args.first));

  // The package has to come from the checkout, or the check proves nothing.
  // meta is printed because the Flutter SDK pins it, and that pin decides
  // which releases of the packages below pub can pick.
  final self = resolved[package];
  print('${package.padRight(20)}${self?.describe() ?? 'missing'}');
  print('${'meta'.padRight(20)}${resolved['meta']?.describe() ?? 'missing'}');

  var failed = self == null || self.source != 'path';
  for (final MapEntry(key: name, value: want) in expected.entries) {
    final got = resolved[name]?.version;
    final ok = got == want;
    if (!ok) failed = true;
    print(
      '${name.padRight(20)}${(got ?? 'missing').padRight(10)}'
      'expected $want${ok ? '' : '  MISMATCH'}',
    );
  }
  if (failed) exit(1);
}

/// Reads the package list from `pub deps --json` output.
///
/// The Flutter tool can print a notice before the JSON on a fresh machine, so
/// parsing starts at the first line that opens an object.
Map<String, _Package> _readVersions(File file) {
  final lines = file.readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('{'));
  if (start < 0) {
    stderr.writeln('no JSON object in ${file.path}');
    exit(1);
  }
  final json = jsonDecode(lines.skip(start).join('\n')) as Map<String, Object?>;
  return {
    for (final package in json['packages'] as List<Object?>)
      if (package case {
        'name': final String name,
        'version': final String version,
        'source': final String source,
      })
        name: _Package(version, source),
  };
}

final class _Package {
  _Package(this.version, this.source);

  final String version;
  final String source;

  String describe() => '$version ($source)';
}
