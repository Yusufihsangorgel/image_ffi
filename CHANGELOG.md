## 1.2.0

- The README now answers, in its first screen, why to reach for this rather
  than the zero-dependency route or the package that already owns the
  category. Both answers carry the file and line, or the issue number, that
  a reader can check. A "reach for it when" list and a sentence on when to
  skip it follow, because a page that only argues for itself is not useful
  for deciding.

## 1.1.4

- Documents how to ship a standalone binary. `dart compile exe` refuses outright
  on a package with a build hook; `dart build cli` runs the hook and writes the
  executable and its library into a `bundle/` directory. The binary resolves the
  library through a relative `../lib`, so a copy of it on its own fails at the
  first call, which is why the whole folder has to ship. Both halves were run to
  produce the output quoted in the README.

## 1.1.3

Documentation and one new example. No API or behaviour change.

- The README now says that phone photos come out upright. `thumbnailJpeg` and
  `thumbnailPng` have read the EXIF orientation tag and applied it since 1.1.0,
  and neither the README nor any example mentioned it. The one thing that
  separates this thumbnailer from a decode-and-resize loop was invisible to
  anyone reading the page. `exifOrientation` and `applyExifOrientation` are in
  the API list now as well.
- `example/upright_thumbnails.dart` takes a 400x300 sensor buffer tagged
  orientation 6 and prints what each path returns: `decodeImage` gives 400x300,
  `thumbnailJpeg` gives 96x128 with nothing passed to it, and the same call with
  `applyOrientation: false` gives 128x96. The README quotes that output.
- The Platforms section reports mobile and desktop Flutter from a run rather
  than a build. An app that encodes and decodes a PNG at startup returns `2x2`
  on an iPhone 17 Pro simulator running iOS 26.5, an Android 15 arm64 emulator
  (API 35) and macOS desktop. A build going green is weaker evidence: `re2`
  1.0.1 built green on Android and threw `dlopen failed` on the first call.

## 1.1.2

- Put the screenshot caption on one line. It was a folded scalar wrapped across
  three lines, and the continuation lines were indented further than the first,
  which keeps the breaks instead of folding them to spaces. The benchmark figure
  on the pub.dev page has therefore been reading `141.` and `7.` as separate
  lines since the caption was added, which makes the one number the chart exists
  to show look wrong. Caption text only; the figure and the measurement behind
  it are unchanged.

`lib/` is byte-identical to 1.1.1.

## 1.1.1

- The example runs without an argument. It used to print a usage line and exit
  64 unless you handed it an image, which is what anyone following the Example
  tab on pub.dev would hit first. It now encodes a 1200x800 gradient with the
  package's own `encodeJpeg` and thumbnails that, so the run shows the whole
  path — read the dimensions without decoding, downscale and re-encode in one
  native call — and reports the thumbnail as a percentage of the source. A path
  argument still works exactly as before.

## 1.1.0

- **Turn phone photos upright.** A camera writes the sensor's pixels unrotated
  and records how the phone was held in the EXIF orientation tag; every viewer
  applies it silently. stb does not parse EXIF, so a portrait photo decoded to
  a landscape buffer and `thumbnailJpeg` produced a sideways thumbnail with
  nothing to indicate anything was wrong — on the most common thumbnail input
  there is.

  `exifOrientation` reads the tag and `applyExifOrientation` applies any of the
  eight values, including the four that swap the axes and the four that mirror.
  `thumbnailJpeg` and `thumbnailPng` now use them by default; pass
  `applyOrientation: false` for the raw sensor framing. A file with no EXIF, a
  malformed tag, or a value outside 1 to 8 reads as upright, so a broken tag
  can never fail a decode that would otherwise have worked.

## 1.0.2

- **Declare the SDK this package can actually resolve on.** The constraint read
  `^3.9.0`, but the `hooks` dependency that runs the native build requires
  `>=3.10.0`. On Dart 3.9 the package looked supported and then failed to
  resolve, with an error naming `hooks` rather than anything the reader had
  asked for. The pubspec and the README now both say 3.10.

## 1.0.1

- **Link libm on Android, where the decoder would otherwise fail at `dlopen`.**
  stb_image calls `pow` for gamma conversion and stb_image_write calls `frexp`
  when writing HDR. Android keeps both in a separate libm, and its linker will
  not resolve a symbol from a library that is absent from `DT_NEEDED`, so the
  shim compiled cleanly and then failed to load on the device. On the 1.0.0
  library `llvm-nm -u --dynamic` reported `U pow` and `U frexp` carrying no
  version tag while every other import carried one, and `DT_NEEDED` listed only
  libdl and libc. Rebuilt, the same commands report `pow@LIBC`, `frexp@LIBC`
  and `ldexp@LIBC`, with `libm.so` in `DT_NEEDED`. Every other target hid the
  omission: macOS and iOS take math from libSystem, and glibc 2.34 folded libm
  into libc. Linux is linked against libm too, because musl and older glibc
  still need it and on modern glibc it costs nothing.

## 1.0.0

The API is stable. No behaviour changes; this freezes the surface after an
adversarial pass over the FFI boundary, and pins what it found as tests.

Verified by execution and now covered by `test/native_safety_test.dart`:

- Undecodable data (garbage, a truncated file, a bare header) raises
  `ImageFfiException`, and an empty buffer raises `ArgumentError` — the split
  the README describes, checked rather than assumed.
- Decoding, resizing and JPEG-encoding 2,000 times grows RSS by about four
  megabytes. Each cycle allocates and frees several native buffers, so leaking
  any of them would cost hundreds.
- `thumbnailJpeg` bounds the longer side and never enlarges an image already
  within the limit.
- A non-positive resize target is rejected instead of reaching the native call.

One honest caveat: the build hooks depend on `native_toolchain_c`, which is
pre-1.0, so a breaking release there may need a new build of this package. It is
a build-time dependency and does not reach the public API frozen here.

## 0.6.0

- Seal `DecodedImage` and `ImageFfiException`. Both carried no class modifier,
  so a 1.0.0 freeze would have made every field added to either one a breaking
  change for anyone who had subclassed it. Neither is meant to be subtyped, and
  nothing in the package, its tests or its example does. `ResizeColorSpace` is
  an enum and was already closed. No behaviour change.

## 0.5.1

- Fix a native buffer leak: `decodeImage`, `resizePixels`, `encodeJpeg`, and
  `encodePng` freed the native output buffer only after copying it into a
  Dart `Uint8List`. If that copy threw (out of memory on a large image), the
  native buffer was never freed. Each free now runs in a `finally` around the
  copy, so it happens whether the copy succeeds or throws.
- Fix a silent truncation risk: `resizePixels` takes `srcWidth`, `srcHeight`,
  `dstWidth`, and `dstHeight` as Dart `int`, but crosses the FFI boundary as a
  32-bit native `Int`. A caller passing a dimension above 2^31-1 got it
  silently wrapped at the boundary instead of an error. These now throw
  `ArgumentError` before the call.

## 0.5.0

- Add `thumbnailJpegBatch` and `thumbnailPngBatch` for processing a folder.
  Running `Future.wait` over `thumbnailJpegAsync` spawned one isolate per image
  at once, each holding a full decoded buffer, which ran a real directory out of
  memory. The batch calls run the same per-image work off the main isolate but
  cap how many isolates are live at once to `concurrency`, defaulting to
  `Platform.numberOfProcessors`, using a semaphore over the existing async
  calls. Each thumbnail is emitted from the returned stream as it finishes, so
  results arrive in completion order rather than input order. `maxDimension` and
  `quality` match the async variants. The README now points at these for a
  folder and `example/no_jank.dart` shows the batch path.

## 0.4.4

- Install instructions now say `pub add` instead of pinning a version. The
  pinned number was stale by several releases and would have been stale again
  after the next one: the README ships frozen in the archive, so a hand-edited
  version line is wrong the moment anything is published. This one cannot go
  out of date.

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
