# image_ffi

Native image decode, resize, and JPEG/PNG encode for Dart, backed by stb over
FFI and compiled at build time by `hook/build.dart`. Callers receive a Dart
`Uint8List`; they never manage native memory.

The pure-Dart `image` package is the default for "resize these images". This
package is narrower — decode (PNG, JPEG, BMP, GIF, PSD, TGA, HDR, PIC),
high-quality resize, JPEG/PNG encode, one-call thumbnails — and faster on that
path. Measured medians of 15 runs, 2000x2000 PNG, longer side 256 px, Apple
M-series (`bench/bench.dart`): decode 21.9 ms vs 94.5 ms, resize 4.8 ms vs
44.0 ms, full pipeline 27.3 ms vs 141.7 ms. Use `image` for WebP/TIFF/GIF/ICO
write, drawing, filters, animation, or a zero-native-dep build.

Unsupported: Dart web (no C compiler, no native assets). Needs a C toolchain.
Linux, macOS, Windows CLI, and Flutter with native assets (iOS, Android,
desktop). SDK `^3.10.0`. `dart compile exe` does not run build hooks.

## Usage

From `example/image_ffi_example.dart`:

```dart
import 'dart:io';

import 'package:image_ffi/image_ffi.dart';

void main(List<String> args) {
  final bytes = File(args.first).readAsBytesSync();
  final info = imageInfo(bytes);
  stdout.writeln('${info.width}x${info.height}, ${info.channels}ch');
  final thumbnail = thumbnailJpeg(bytes, maxDimension: 256, quality: 85);
  File('${args.first}.thumb.jpg').writeAsBytesSync(thumbnail);
}
```

Pieces: `decodeImage`, `resizePixels`, `encodeJpeg` / `encodePng`.
`thumbnailPng` keeps alpha; JPEG drops it. Off the UI isolate:
`thumbnailJpegAsync` / `thumbnailPngAsync`. A folder: `thumbnailJpegBatch` /
`thumbnailPngBatch` (completion order, not input order). Do not `Future.wait`
the async calls — one isolate per image, each holding a full decode.

## Contracts

**Native memory.** `decodeImage`, `resizePixels`, `encodeJpeg`, and `encodePng`
copy the native buffer into a Dart `Uint8List` and free it before returning
(`imgffiFreeImage` for decode, `imgffiFreeBuffer` for resize/encode, in
`lib/src/bindings.dart`). `DecodedImage.pixels` is Dart-owned. Nothing to free.

**Pixel layout.** `DecodedImage`: row-major from the top-left, no row padding,
`pixels.length == width * height * channels`. Order is R, G, B, then A.
`channels`: 1 = gray, 2 = gray+alpha, 3 = RGB, 4 = RGBA (non-premultiplied).
`resizePixels` defaults `channels` to 4, `encodeJpeg` to 3, `encodePng` to 4.
Always pass `channels: image.channels`. `forceChannels` on `decodeImage` is 1–4;
omit it for the file's native count.

**Resize quality and colour space.** `resizePixels` has no quality argument; the
filter is always stb_image_resize2. `quality` (1–100) is JPEG encode only:
`encodeJpeg` default 90, `thumbnailJpeg` default 85. `colorSpace` defaults to
`ResizeColorSpace.srgb` (convert to linear light, resample, convert back) —
photographs and UI. `ResizeColorSpace.linear` skips the curve — masks, depth,
already-linear data. Alpha is always resampled linearly. 2-channel input is
gray+alpha, not two colour channels. A checkerboard downscale lands on 188 with
`srgb` and 127 with `linear` (`example/gamma_correct_resize.dart`). Getting this
wrong does not throw.

**EXIF.** `decodeImage` returns the sensor buffer; stb does not parse EXIF.
`thumbnailJpeg` and `thumbnailPng` default `applyOrientation: true`.
`exifOrientation` reads a JPEG tag (1–8) and returns 1 if missing, malformed,
or not JPEG. `applyExifOrientation` treats a value outside 1–8 as 1. Phone JPEG
tagged 6: `decodeImage` is 400x300, `thumbnailJpeg` is 96x128, with
`applyOrientation: false` it is 128x96 (`example/upright_thumbnails.dart`).
The async thumbnail functions always apply orientation (no parameter).

**Integer bounds.** Width, height, `dstWidth`, `dstHeight`, and `maxDimension`
must be positive. `resizePixels` also rejects a dimension `> 2147483647`
(`0x7FFFFFFF`) so it is not truncated as a 32-bit FFI `Int`. `thumbnailJpeg` /
`thumbnailPng` never enlarge; the longer side is at most `maxDimension`.

Invalid image data throws `ImageFfiException` (stb's reason). Bad arguments
throw `ArgumentError`.

## Mistakes

Decode a JPEG (3 channels) then `resizePixels` without `channels` (default 4):

```
Invalid argument (pixels.length): must equal srcWidth * srcHeight * channels (256): 192
```

Same trap: `encodePng` default 4 on JPEG pixels; `encodeJpeg` default 3 on RGBA
(256 vs 192, reversed). Fix: `channels: image.channels`.

`forceChannels: 0` meaning "native":

```
Invalid argument (forceChannels): must be between 1 and 4: 0
```

Fix: omit `forceChannels`.

Empty buffer:

```
Invalid argument (bytes): must not be empty: _Uint8List
```

Bytes that are not an image:

```
ImageFfiException: unknown image type
```

`quality: 0` (or 101):

```
Invalid argument (quality): must be between 1 and 100: 0
```

`maxDimension: 0` or `dstWidth: 0`:

```
Invalid argument (maxDimension): must be positive: 0
Invalid argument (dstWidth): must be positive: 0
```

A resize dimension above `Int32`:

```
Invalid argument (dstWidth): must not exceed 2147483647, the largest value a native Int parameter can carry without truncating: 4294967396
```

`dart compile exe` on a program that depends on this package:

```
'dart compile' does not support build hooks, use 'dart build' instead.
```

Fix: `dart build cli` and ship the whole `bundle/`. The binary alone fails with
`Failed to load dynamic library '../lib/libimage_ffi_shim.dylib'`.

`thumbnailJpegBatch(..., concurrency: 0)`:

```
Invalid argument (concurrency): must be positive: 0
```

## Layout

- `lib/image_ffi.dart` — public exports. Implementation: `lib/src/image_ffi_base.dart`, EXIF in `lib/src/exif.dart`, `@Native` in `lib/src/bindings.dart`.
- `hook/build.dart` — `CBuilder.library(name: 'image_ffi_shim')` compiles `src/image_ffi_shim.c` with includes `src/third_party/stb` and `src`. Asset id is `src/bindings.dart`. Links `m` on Android and Linux.
- `example/`, `test/`, `bench/bench.dart`.
- Tests: `dart test`. Analyze: `dart analyze --fatal-infos`. Format: `dart format --output=none --set-exit-if-changed .`. First run compiles the native library (C toolchain required). Public API must have dartdoc (`public_member_api_docs`).
