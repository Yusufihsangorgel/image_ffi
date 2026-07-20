/// Native image decode, resize and encode for Dart, backed by Sean Barrett's
/// stb single-file libraries over FFI.
///
/// The stb C sources are compiled from source by a Dart build hook, so there
/// is no prebuilt binary to ship and no system library to install beyond a C
/// toolchain. Decoding, resizing and encoding run in native code and copy the
/// result into a Dart `Uint8List`, so callers never manage native memory.
///
/// ```dart
/// import 'dart:io';
/// import 'package:image_ffi/image_ffi.dart';
///
/// void main() {
///   final bytes = File('photo.jpg').readAsBytesSync();
///   final thumb = thumbnailJpeg(bytes, maxDimension: 256);
///   File('thumb.jpg').writeAsBytesSync(thumb);
/// }
/// ```
///
/// See [decodeImage], [imageInfo], [resizePixels], [encodeJpeg], [encodePng]
/// and [thumbnailJpeg] for the full API.
library;

export 'src/image_ffi_base.dart'
    show
        DecodedImage,
        ImageFfiException,
        ResizeColorSpace,
        decodeImage,
        encodeJpeg,
        encodePng,
        imageInfo,
        resizePixels,
        thumbnailJpeg,
        thumbnailJpegAsync,
        thumbnailPng,
        thumbnailPngAsync;
