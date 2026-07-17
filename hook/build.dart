import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the C shim and the three vendored stb single-file libraries into a
/// dynamic library at build time.
///
/// `src/image_ffi_shim.c` is the only translation unit that defines the
/// `STB_*_IMPLEMENTATION` macros, so the stb code is compiled exactly once and
/// nothing is generated at build time. The include roots are the vendored stb
/// directory (so `#include "stb_image.h"` resolves) and `src` itself. The
/// library is registered under the asset id of `lib/src/bindings.dart`, so the
/// `@Native` symbols in that file resolve to it.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final targetOS = input.config.code.targetOS;

    final builder = CBuilder.library(
      name: 'image_ffi_shim',
      assetName: 'src/bindings.dart',
      sources: ['src/image_ffi_shim.c'],
      includes: ['src/third_party/stb', 'src'],
      // stb_image_write uses sprintf, which MSVC flags as insecure and, with
      // warnings-as-errors, would fail the build. stb is otherwise portable
      // and needs no POSIX feature macros.
      defines: {if (targetOS == OS.windows) '_CRT_SECURE_NO_WARNINGS': null},
      language: Language.c,
    );
    await builder.run(input: input, output: output);
  });
}
