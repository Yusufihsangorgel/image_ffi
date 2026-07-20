## 0.4.3

- Widen the native-toolchain constraints so the package can be installed in a
  Flutter app at all. `hooks` 2.1.0 and `native_toolchain_c` 0.19.3 raised their
  `meta` floor to ^1.19.0, and Flutter's SDK pins `meta` to 1.17.0, so
  `flutter pub add` failed at version solving with "flutter from sdk is
  incompatible". Allowing `hooks >=2.0.2` and `native_toolchain_c >=0.19.2`
  lets the solver pick a version that works with the pinned `meta`, while a
  pure-Dart project still resolves to the newest. No API or behaviour change.

## 0.4.2

- `example/no_jank.dart` measures what the async variants are for. It builds a
  4000x3000 JPEG so no file is needed, makes eight thumbnails on the main
  isolate and eight with `thumbnailJpegAsync`, and runs a 16 ms timer alongside
  to report the longest gap between two ticks. On this machine: 413 ms of
  silence, about 25 frames, against 18 ms and one. The work takes the same time
  either way, which is the point; what moves is where it happens.
- `example/README.md` says which call to reach for and why the thumbnail
  functions exist at all, given the three-step version crosses the FFI boundary
  three times and holds the full-size pixel buffer in Dart in between.

## 0.4.1

- Declare the benchmark chart in `pubspec.yaml` so pub.dev renders it on the
  package page. The chart was already in the repository and the README, but
  pub.dev shows only what the `screenshots:` field points at, so the page a
  reader lands on from search opened with text where the measurement should
  have been.

## 0.4.0

- Add `thumbnailJpegAsync` and `thumbnailPngAsync`. They take the same
  arguments as the synchronous versions and return a `Future`, running the whole
  decode, resize and encode on a background isolate with `Isolate.run` so a
  large image doesn't block the calling isolate. In a Flutter app this keeps the
  UI responsive while a picked photo is turned into a thumbnail, which neither
  the pure-Dart `image` package nor a synchronous FFI call can do on the main
  isolate. An `ImageFfiException` raised in the worker surfaces from the future.

## 0.3.0

- Add `thumbnailPng`, a one-call decode, resize, and PNG encode that keeps the
  alpha channel. Reach for it on logos, icons, screenshots, and anything with
  transparency, where `thumbnailJpeg` would flatten the transparent areas onto a
  background.

## 0.2.1

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.2.0

- `resizePixels` now takes a `colorSpace` (`ResizeColorSpace.srgb` by default,
  or `.linear`). sRGB is right for photographic and UI images; linear is for
  masks and data pixels where an sRGB curve would distort the values.
- Fix: 2-channel input is now resampled as grayscale + alpha (STBIR_RA) instead
  of two colour channels, so edges against transparency stay clean for gray+alpha
  images. Previously a 2-channel resize let transparent pixels bleed into the
  colour.

## 0.1.0

- Initial release.
- Decode PNG, JPEG, BMP, GIF, PSD, TGA, HDR and PIC from memory
  (`decodeImage`), with an optional forced channel count.
- Read dimensions and channel count without decoding pixels (`imageInfo`).
- High-quality, sRGB-correct resize (`resizePixels`).
- JPEG and PNG encoding to memory (`encodeJpeg`, `encodePng`).
- One-call thumbnail generation (`thumbnailJpeg`): decode, aspect-preserving
  downscale and JPEG encode.
- Native stb sources compiled from source by a Dart build hook; no prebuilt
  binaries.
