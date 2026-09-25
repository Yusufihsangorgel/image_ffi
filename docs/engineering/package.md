# Package engineering rules: image_ffi

Rules-Version: image_ffi/06d2973984493d231866d28039eb99146624486d798f2e3850db943ab074365b
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: aea46b7
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD aea46b7 (1.2.6). One C shim over vendored stb (image v2.30, resize2, write). The Dart side has one large core file (image_ffi_base.dart, 667 lines). This file contains the types, validation helpers, native decode/info/resize/encode paths, thumbnail pipelines, async variants via `Isolate.run`, and the semaphore-based `mapBounded` batch engine. `exif.dart` is a pure Dart EXIF orientation reader and applier. Native errors arrive as `nullptr`/0 returns and are converted to `ImageFfiException`. The message is the thread-local reason from stb. Among the siblings, this package has the strictest analysis settings. Structural flaws: an import cycle between base and exif, duplicate bodies in the two thumbnail pipelines, and missing parameters in the async/batch versions.

## Layers and responsibilities
- lib/image_ffi.dart: Only `export ... show` (lines 24-40).
- lib/src/image_ffi_base.dart: DecodedImage, ImageFfiException, ResizeColorSpace; `_check*` validation; native paths; thumbnail; async; batch (`_Semaphore`, `mapBounded`).
- lib/src/exif.dart: `exifOrientation` (never throws), `applyExifOrientation`.
- lib/src/bindings.dart: 8 `@Native` (decode, info, resize, encode_png, encode_jpg, two free functions, failure_reason) plus allocateBytes/freeBytes.
- src/image_ffi_shim.c, src/third_party/stb/: A 200-line shim, `IMGFFI_EXPORT`, stb implementation macros in one TU.
- hook/build.dart: Early return on `buildCodeAssets`, Windows `_CRT_SECURE_NO_WARNINGS`, Android/Linux `m`.
- test/, example/, tool/gamma_figure.dart, bench/: 9 test files; 4 examples; a gamma figure; a bench with a package:image comparison.

## Public API and dependency direction
Functions: decodeImage(bytes, {forceChannels}), imageInfo (returns the record `({int width, int height, int channels})`), resizePixels({srcWidth, srcHeight, dstWidth, dstHeight, channels=4, colorSpace=srgb}), encodeJpeg({width, height, channels=3, quality=90}), encodePng({channels=4}), thumbnailJpeg({maxDimension=256, quality=85, applyOrientation=true}), thumbnailPng({maxDimension, applyOrientation}), thumbnailJpegAsync, thumbnailPngAsync, thumbnailJpegBatch({concurrency}), thumbnailPngBatch, exifOrientation, applyExifOrientation. Types: DecodedImage, ImageFfiException, ResizeColorSpace {srgb, linear}. `mapBounded` is public in src but not exported. Only test/batch_thumbnail_test.dart:7 uses it. The boundary is lib/image_ffi.dart:24-40.

image_ffi.dart -> {image_ffi_base, exif}. image_ffi_base -> bindings, exif (orientation handling for thumbnails), package:ffi, dart:isolate, dart:io (Platform). exif -> image_ffi_base (DecodedImage only). This is a CYCLE (image_ffi_base.dart:9 <-> exif.dart:3). bindings -> dart:ffi, package:ffi. package:image is a dev dependency only: test/image_ffi_test.dart and bench/bench.dart.

## Error, state and platform contracts
- Dart validation before native calls: `_checkPositive`, `_checkInt32` (native `Int` is 32 bit), `_checkChannels` (1-4), `_checkPixelLength`. All raise `ArgumentError.value` (image_ffi_base.dart:489-526).
- `_copyToNative` plus nested try/finally. The free call matches the source: decode -> `imgffiFreeImage`, resize/encode -> `imgffiFreeBuffer`, Dart allocation -> `freeBytes` (image_ffi_base.dart:71-80, 111-147, 257-280).
- Native error: `nullptr`/0 -> `ImageFfiException(_failureReason())`. The stb reason is assembled from a thread-local (stb_image.h:625-631; image_ffi_base.dart:62-69).
- Async: a synchronous function inside `Isolate.run` (image_ffi_base.dart:540-555). Batch: `_Semaphore` + `Stream.fromFutures`. Results arrive in completion order. Errors surface as stream events. The default concurrency is `Platform.numberOfProcessors` (image_ffi_base.dart:557-667).
- EXIF never throws on malformed data. It returns 1 (exif.dart:14-16, 17-50, 106-133).
- The default color space is sRGB with gamma-correct resampling (image_ffi_base.dart:196-206).
- Strict analysis: strict-casts/inference/raw-types plus public_member_api_docs (analysis_options.yaml:3-11).
- Justified `platforms:` declaration: android, ios, linux, macos, windows (pubspec.yaml:26-33).
- Global state is only `const _int32Max`. A semaphore is created per call.
- Documentation layout: AGENTS.md targets users (Usage/Contracts/Mistakes/Layout).

## Package rules
### image_ffi/IF-01 [MUST]
The public API is exposed only through the `lib/image_ffi.dart` show lists. Helpers kept public in src for tests, such as `mapBounded`, are not exported; tests take them with `show` through `package:image_ffi/src/...`.
Reason: The batch engine is an internal contract; it must not leak into the public API.
Evidence: lib/image_ffi.dart:24-40; lib/src/image_ffi_base.dart:595-598; test/batch_thumbnail_test.dart:7
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-02 [MUST]
Every dimension, channel and length going to native is validated in Dart with `_check*` helpers and `ArgumentError.value`. A new dimension passed to a native `Int` parameter goes through `_checkInt32`.
Reason: `@Native` `Int` is 32 bit; an unchecked value silently wraps at the FFI boundary.
Evidence: lib/src/image_ffi_base.dart:239-255, 489-526; lib/src/bindings.dart:56-67
Evidence role: current-pattern
Existing violation: image_ffi-D005

### image_ffi/IF-03 [MUST]
A buffer returned by native code is released with its own free function: `imgffiDecode` -> `imgffiFreeImage`, resize/encode -> `imgffiFreeBuffer`, a Dart allocation -> `freeBytes`. The result is first copied with `Uint8List.fromList`; all of it sits in nested try/finally.
Reason: stb allocations and shim allocations are separate; a wrong free or a leak is invisible in native memory.
Evidence: lib/src/image_ffi_base.dart:111-147, 257-280, 309-331; lib/src/bindings.dart:12-16, 36-38, 97-100
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-04 [MUST]
A native failure is reported as a `nullptr`/0 return and converted to `ImageFfiException`; when there is an stb reason, it enters the message through `_failureReason()`. No new exception type is introduced.
Reason: A single native error type; the message carries stb's concrete reason.
Evidence: lib/src/image_ffi_base.dart:15-29, 62-69, 124-126, 180-182; src/image_ffi_shim.c:198-199
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-05 [MUST]
The EXIF reader does not throw on corrupt or missing data; it returns 1. `applyExifOrientation` treats anything outside 1..8 as 1.
Reason: A corrupt tag must not fail the decode (dartdoc contract).
Evidence: lib/src/exif.dart:14-16, 52-58; test/exif_bounds_test.dart:70
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-06 [MUST]
The async and batch variants are thin wrappers only. The work runs through the sync function inside `Isolate.run`; a batch limits concurrency with `mapBounded`, results arrive in completion order, and errors are delivered as stream events. Every parameter of the sync version is passed on.
Reason: A single implementation of the logic; the async surface must not duplicate behavior.
Evidence: lib/src/image_ffi_base.dart:540-555, 587-616, 641-667
Evidence role: both
Existing violation: image_ffi-D002

### image_ffi/IF-07 [MUST]
The `ResizeColorSpace.srgb` default is kept; a change to color handling updates test/resize_colorspace_test.dart.
Reason: Gamma-correct downscaling is the package's documented differentiator (doc/gamma-resize.png).
Evidence: lib/src/image_ffi_base.dart:196-206, 237; test/resize_colorspace_test.dart:7
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-08 [MUST_NOT]
strict-casts, strict-inference, strict-raw-types and public_member_api_docs in analysis_options.yaml are not relaxed and are not silenced with `// ignore`.
Reason: The strictest settings among the siblings; there are no ignore comments in lib today.
Evidence: analysis_options.yaml:1-11
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-09 [MUST]
Only `src/image_ffi_shim.c` defines the stb `*_IMPLEMENTATION` macros (single TU). The hook keeps the `buildCodeAssets` early return, the Windows define and the Android/Linux `m` link, with justification comments.
Reason: stb must be compiled once; a missing libm on Android gives a dlopen error on device.
Evidence: hook/build.dart:8-13, 18, 27-44
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-10 [SHOULD]
The `platforms:` declaration (android, ios, linux, macos, windows) stays aligned with CI and Flutter runs; web is not added.
Reason: The declaration is deliberate rather than inferred; there is no dart:ffi on the web.
Evidence: pubspec.yaml:26-33
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-11 [MUST_NOT]
`package:image` stays a dev_dependency only (tests and the bench comparison); lib/ does not depend on it.
Reason: Limit tests run with an independent decoder; the burden must not be pushed onto consumers.
Evidence: pubspec.yaml:42; test/image_ffi_test.dart; bench/bench.dart
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-12 [MUST]
Package level contains only `const` fields; concurrency state (`_Semaphore`) is created per call and is not shared.
Reason: There is no shared mutable state between isolate and batch calls.
Evidence: lib/src/image_ffi_base.dart:498, 603-604
Evidence role: current-pattern
Existing violation: none

### image_ffi/IF-13 [MUST]
A new native operation follows this skeleton: `_check*` validation -> `_copyToNative` -> the native call -> `ImageFfiException` on `nullptr` -> the `Uint8List.fromList` copy -> the free matching the source, all in nested try/finally. An async or batch version is not coded separately; it is provided through an `Isolate.run`/`mapBounded` wrapper.
Reason: The current extension point; the FFI skeleton and the concurrency engine must not be duplicated.
Evidence: lib/src/image_ffi_base.dart:294-332, 344-371, 540-555, 641-667
Evidence role: current-pattern
Existing violation: none

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed .; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:25.
- Working directory: repository root; command: dart test; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:26.
Not verified by the survey:
- `dart analyze`/`dart test` were not run (read-only scope).
- The thread-local behavior of the stb failure reason was inferred from the conditional macros at stb_image.h:625-631. The hook does not set `std:`. The behavior was therefore not verified on every target compiler.
- The behavior of running isolates when the batch stream subscription is cancelled was not measured.
- The android/ios declaration has no CI counterpart. Evidence of 'Flutter runs' was not searched in the repository. The CHANGELOG references 1.2.4 and it was not read.
- The shim (200 lines) was scanned only through its export and failure_reason markers.

## Existing debt
The complete register is docs/engineering/debt.json.
- image_ffi-D001 | small | lib/src/image_ffi_base.dart:400-427 <-> 452-479; 304-306 <-> 396-398; 248-255 <-> 517-526 | duplicated logic
  Fix: A private `_decodeFitted(imageBytes, maxDimension, applyOrientation)` helper + `_checkQuality`; resizePixels uses a `_checkPixelLength` that takes the parameter names. The existing tests must pass unchanged.
  Closure: thumbnailJpeg and thumbnailPng share one private _decodeFitted helper, quality is checked in a single _checkQuality and resizePixels reuses a parameter-aware _checkPixelLength. The existing tests pass unchanged.
- image_ffi-D002 | small | lib/src/image_ffi_base.dart:540-555, 641-667 (<-> 393, 448) | API inconsistency
  Fix: Add an optional `applyOrientation = true` parameter and pass it through (not breaking); a test with `applyOrientation: false` for async and batch.
  Closure: thumbnailJpegAsync, thumbnailPngAsync, thumbnailJpegBatch and thumbnailPngBatch accept applyOrientation defaulting to true and pass it to the sync functions. A test exercises applyOrientation: false on the async and batch paths.
- image_ffi-D003 | small | lib/src/image_ffi_base.dart:9 <-> lib/src/exif.dart:3 | import cycle
  Fix: Move `DecodedImage` to `lib/src/decoded_image.dart`; base and exif import it, the export line is updated, and the API does not change.
  Closure: DecodedImage is defined in lib/src/decoded_image.dart and image_ffi_base.dart and exif.dart import it from there. The export line in lib/image_ffi.dart keeps the same public names.
- image_ffi-D004 | small | lib/src/image_ffi_base.dart:39-46 | unenforced precondition
  Fix: Add an assert to the ctor + a debug test (release behavior unchanged).
  Closure: The DecodedImage constructor asserts pixels.length == width * height * channels. A debug test constructs an invalid DecodedImage and expects the assert to fire.
- image_ffi-D005 | small | lib/src/image_ffi_base.dart:301-307, 350-353 (<-> 243-246) | inconsistent validation
  Fix: Add the same check.
  Closure: encodeJpeg and encodePng pass width and height through _checkInt32 before the native call, matching resizePixels.
- image_ffi-D006 | medium | lib/src/image_ffi_base.dart:163 | evolvability (design debt)
  Fix: Enter it in the debt register; in the next major, move `ImageInfo` to a final class or add a new API that keeps the record.
  Closure: The record return type of imageInfo is tracked in the debt register. A later major version ships ImageInfo as a final class or adds a new API that keeps the record.
