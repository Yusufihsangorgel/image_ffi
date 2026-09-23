import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';

import '../hook/build.dart' as build_hook;

void main() {
  test('the build hook returns without output when no code assets are '
      'requested', () async {
    await testBuildHook(
      mainMethod: build_hook.main,
      extensions: [],
      check: (input, output) {
        expect(input.config.buildCodeAssets, isFalse);
        expect(output.assets.encodedAssets, isEmpty);
      },
    );
  });
}
