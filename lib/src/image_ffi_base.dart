import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';

/// Thrown when a native stb operation fails, for example when [decodeImage] is
/// given bytes that are not a recognised image.
///
/// The [message] is stb's own diagnostic (`stbi_failure_reason`) when one is
/// available, so it names the specific reason the operation failed.
class ImageFfiException implements Exception {
  /// Creates an exception with a human-readable [message].
  ImageFfiException(this.message);

  /// A short description of what went wrong.
  final String message;

  @override
  String toString() => 'ImageFfiException: $message';
}

/// A decoded image: raw 8-bit pixels plus their geometry.
///
/// The [pixels] are stored row-major from the top-left, with [channels] bytes
/// per pixel and no row padding, so the total length is
/// `width * height * channels`. Channel order is red, green, blue, alpha for
/// four-channel images and red, green, blue for three-channel images; a single
/// channel is grayscale.
class DecodedImage {
  /// Creates a decoded image. The caller must ensure `pixels.length` equals
  /// `width * height * channels`.
  DecodedImage({
    required this.width,
    required this.height,
    required this.channels,
    required this.pixels,
  });

  /// The image width in pixels.
  final int width;

  /// The image height in pixels.
  final int height;

  /// The number of bytes per pixel: 1 (grayscale), 2 (grayscale + alpha),
  /// 3 (RGB) or 4 (RGBA).
  final int channels;

  /// The raw pixel bytes, row-major, `width * height * channels` long.
  final Uint8List pixels;
}

/// Reads stb's most recent failure reason, falling back to a generic message.
String _failureReason() {
  final reason = imgffiFailureReason();
  if (reason == nullptr) {
    return 'unknown image error';
  }
  return reason.toDartString();
}

/// Copies [bytes] into freshly allocated native memory.
///
/// The returned pointer must be released with [freeBytes]. Native memory is
/// invisible to the Dart garbage collector, so every call is paired with a
/// `finally` that frees it.
Pointer<Uint8> _copyToNative(Uint8List bytes) {
  final pointer = allocateBytes(bytes.length);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

/// Decodes an encoded image into raw pixels.
///
/// Supports every format stb_image reads: PNG, JPEG, BMP, GIF, PSD, TGA, HDR
/// and PIC. The result's [DecodedImage.channels] is the image's native channel
/// count unless [forceChannels] is given.
///
/// Set [forceChannels] to 1 (grayscale), 2 (grayscale + alpha), 3 (RGB) or 4
/// (RGBA) to convert during decode; this is the cheapest way to get a uniform
/// layout, for example forcing 4 so every image is RGBA.
///
/// ```dart
/// final image = decodeImage(await File('photo.jpg').readAsBytes());
/// print('${image.width}x${image.height}, ${image.channels} channels');
/// ```
///
/// Throws an [ArgumentError] if [bytes] is empty or [forceChannels] is out of
/// range, and an [ImageFfiException] if the bytes are not a decodable image.
DecodedImage decodeImage(Uint8List bytes, {int? forceChannels}) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
  }
  if (forceChannels != null && (forceChannels < 1 || forceChannels > 4)) {
    throw ArgumentError.value(
      forceChannels,
      'forceChannels',
      'must be between 1 and 4',
    );
  }

  final dataPtr = _copyToNative(bytes);
  final outWidth = malloc<Int>();
  final outHeight = malloc<Int>();
  final outChannels = malloc<Int>();
  try {
    final pixelsPtr = imgffiDecode(
      dataPtr,
      bytes.length,
      forceChannels ?? 0,
      outWidth,
      outHeight,
      outChannels,
    );
    if (pixelsPtr == nullptr) {
      throw ImageFfiException(_failureReason());
    }
    final width = outWidth.value;
    final height = outHeight.value;
    final channels = outChannels.value;
    final length = width * height * channels;
    final pixels = Uint8List.fromList(pixelsPtr.asTypedList(length));
    imgffiFreeImage(pixelsPtr);
    return DecodedImage(
      width: width,
      height: height,
      channels: channels,
      pixels: pixels,
    );
  } finally {
    freeBytes(dataPtr);
    malloc.free(outWidth);
    malloc.free(outHeight);
    malloc.free(outChannels);
  }
}

/// Reads an image's dimensions and channel count without decoding its pixels.
///
/// This parses only the header, so it is far cheaper than [decodeImage] when
/// all you need is the size. The channel count is the image's native value and
/// matches what [decodeImage] returns with no `forceChannels`.
///
/// ```dart
/// final info = imageInfo(bytes);
/// print('${info.width}x${info.height}');
/// ```
///
/// Throws an [ArgumentError] if [bytes] is empty and an [ImageFfiException] if
/// the header cannot be parsed.
({int width, int height, int channels}) imageInfo(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
  }

  final dataPtr = _copyToNative(bytes);
  final outWidth = malloc<Int>();
  final outHeight = malloc<Int>();
  final outChannels = malloc<Int>();
  try {
    final ok = imgffiInfo(
      dataPtr,
      bytes.length,
      outWidth,
      outHeight,
      outChannels,
    );
    if (ok != 1) {
      throw ImageFfiException(_failureReason());
    }
    return (
      width: outWidth.value,
      height: outHeight.value,
      channels: outChannels.value,
    );
  } finally {
    freeBytes(dataPtr);
    malloc.free(outWidth);
    malloc.free(outHeight);
    malloc.free(outChannels);
  }
}

/// The colour space a resize resamples in.
enum ResizeColorSpace {
  /// Treat the colour channels as sRGB, converting to linear light for the
  /// resample and back. The right default for photographic and UI images.
  srgb,

  /// Treat the colour channels as already linear. Use this for masks, data
  /// images, or pixels you keep in linear space, where applying an sRGB curve
  /// would distort the values.
  linear,
}

/// Resizes raw pixels to new dimensions with a high-quality filter.
///
/// The input is [srcWidth] by [srcHeight] with [channels] bytes per pixel,
/// row-major and unpadded, so `pixels.length` must equal
/// `srcWidth * srcHeight * channels`. The output is the same layout at
/// [dstWidth] by [dstHeight].
///
/// [colorSpace] selects how the colour channels are treated: [ResizeColorSpace.srgb]
/// (the default) resamples in linear light, correct for photographic and UI
/// images; [ResizeColorSpace.linear] treats the pixels as already linear, for
/// masks or data where an sRGB curve would be wrong. Alpha is always resampled
/// linearly. The channel count picks the right layout, so 2-channel input is
/// treated as grayscale + alpha (not two colour channels) and 4-channel as
/// non-premultiplied RGBA, keeping edges against transparency clean.
///
/// This operates on already-decoded pixels; use [thumbnailJpeg] for the common
/// decode-then-downscale-then-encode path.
///
/// Throws an [ArgumentError] if any dimension is not positive, [channels] is
/// out of range, or `pixels.length` does not match, and an [ImageFfiException]
/// if the native resize fails.
Uint8List resizePixels(
  Uint8List pixels, {
  required int srcWidth,
  required int srcHeight,
  required int dstWidth,
  required int dstHeight,
  int channels = 4,
  ResizeColorSpace colorSpace = ResizeColorSpace.srgb,
}) {
  _checkPositive(srcWidth, 'srcWidth');
  _checkPositive(srcHeight, 'srcHeight');
  _checkPositive(dstWidth, 'dstWidth');
  _checkPositive(dstHeight, 'dstHeight');
  _checkChannels(channels);
  final expected = srcWidth * srcHeight * channels;
  if (pixels.length != expected) {
    throw ArgumentError.value(
      pixels.length,
      'pixels.length',
      'must equal srcWidth * srcHeight * channels ($expected)',
    );
  }

  final srcPtr = _copyToNative(pixels);
  try {
    final outPtr = imgffiResize(
      srcPtr,
      srcWidth,
      srcHeight,
      dstWidth,
      dstHeight,
      channels,
      colorSpace == ResizeColorSpace.linear ? 1 : 0,
    );
    if (outPtr == nullptr) {
      throw ImageFfiException('resize failed');
    }
    final result = Uint8List.fromList(
      outPtr.asTypedList(dstWidth * dstHeight * channels),
    );
    imgffiFreeBuffer(outPtr);
    return result;
  } finally {
    freeBytes(srcPtr);
  }
}

/// Encodes raw pixels as a JPEG.
///
/// The input is [width] by [height] with [channels] bytes per pixel (1
/// grayscale, 3 RGB, or 4 RGBA with the alpha channel ignored), row-major and
/// unpadded, so `pixels.length` must equal `width * height * channels`.
/// [quality] runs from 1 to 100; 90 is a good default and higher values trade
/// size for fidelity.
///
/// Throws an [ArgumentError] if any dimension is not positive, [channels] or
/// [quality] is out of range, or `pixels.length` does not match, and an
/// [ImageFfiException] if encoding fails.
Uint8List encodeJpeg(
  Uint8List pixels, {
  required int width,
  required int height,
  int channels = 3,
  int quality = 90,
}) {
  _checkPositive(width, 'width');
  _checkPositive(height, 'height');
  _checkChannels(channels);
  if (quality < 1 || quality > 100) {
    throw ArgumentError.value(quality, 'quality', 'must be between 1 and 100');
  }
  _checkPixelLength(pixels, width, height, channels);

  final srcPtr = _copyToNative(pixels);
  final outLen = malloc<Int>();
  try {
    final outPtr = imgffiEncodeJpg(
      srcPtr,
      width,
      height,
      channels,
      quality,
      outLen,
    );
    if (outPtr == nullptr) {
      throw ImageFfiException('JPEG encoding failed');
    }
    final result = Uint8List.fromList(outPtr.asTypedList(outLen.value));
    imgffiFreeBuffer(outPtr);
    return result;
  } finally {
    freeBytes(srcPtr);
    malloc.free(outLen);
  }
}

/// Encodes raw pixels as a PNG.
///
/// The input is [width] by [height] with [channels] bytes per pixel (1
/// grayscale, 2 grayscale + alpha, 3 RGB, or 4 RGBA), row-major and unpadded,
/// so `pixels.length` must equal `width * height * channels`. PNG is lossless,
/// so decoding the result reproduces [pixels] exactly.
///
/// Throws an [ArgumentError] if any dimension is not positive, [channels] is
/// out of range, or `pixels.length` does not match, and an [ImageFfiException]
/// if encoding fails.
Uint8List encodePng(
  Uint8List pixels, {
  required int width,
  required int height,
  int channels = 4,
}) {
  _checkPositive(width, 'width');
  _checkPositive(height, 'height');
  _checkChannels(channels);
  _checkPixelLength(pixels, width, height, channels);

  final srcPtr = _copyToNative(pixels);
  final outLen = malloc<Int>();
  try {
    final outPtr = imgffiEncodePng(srcPtr, width, height, channels, outLen);
    if (outPtr == nullptr) {
      throw ImageFfiException('PNG encoding failed');
    }
    final result = Uint8List.fromList(outPtr.asTypedList(outLen.value));
    imgffiFreeBuffer(outPtr);
    return result;
  } finally {
    freeBytes(srcPtr);
    malloc.free(outLen);
  }
}

/// Decodes an image, downscales it so its longer side is at most
/// [maxDimension], and JPEG-encodes the result, all in one call.
///
/// This is the fast path for thumbnails: decode, aspect-preserving resize and
/// encode happen natively with a single copy back into Dart. The aspect ratio
/// is preserved and the image is never enlarged, so an image already within
/// [maxDimension] is only re-encoded at [quality]. Four-channel images encode
/// as JPEG with alpha dropped.
///
/// ```dart
/// final thumb = thumbnailJpeg(await File('photo.jpg').readAsBytes());
/// await File('thumb.jpg').writeAsBytes(thumb);
/// ```
///
/// Throws an [ArgumentError] if [maxDimension] is not positive or [quality] is
/// out of range, and an [ImageFfiException] if the input cannot be decoded.
Uint8List thumbnailJpeg(
  Uint8List imageBytes, {
  int maxDimension = 256,
  int quality = 85,
}) {
  _checkPositive(maxDimension, 'maxDimension');
  if (quality < 1 || quality > 100) {
    throw ArgumentError.value(quality, 'quality', 'must be between 1 and 100');
  }

  final image = decodeImage(imageBytes);
  final longerSide = math.max(image.width, image.height);

  int dstWidth;
  int dstHeight;
  Uint8List pixels;
  if (longerSide <= maxDimension) {
    dstWidth = image.width;
    dstHeight = image.height;
    pixels = image.pixels;
  } else {
    final scale = maxDimension / longerSide;
    dstWidth = math.max(1, (image.width * scale).round());
    dstHeight = math.max(1, (image.height * scale).round());
    pixels = resizePixels(
      image.pixels,
      srcWidth: image.width,
      srcHeight: image.height,
      dstWidth: dstWidth,
      dstHeight: dstHeight,
      channels: image.channels,
    );
  }

  return encodeJpeg(
    pixels,
    width: dstWidth,
    height: dstHeight,
    channels: image.channels,
    quality: quality,
  );
}

/// Decodes [imageBytes], scales it so its longer side is at most [maxDimension],
/// and re-encodes it as PNG.
///
/// Unlike [thumbnailJpeg], this keeps an alpha channel, so it is the one to reach
/// for on logos, icons, screenshots, and anything with transparency, where a
/// JPEG would flatten the transparent areas onto an opaque background. PNG is
/// lossless, so there is no quality knob.
Uint8List thumbnailPng(Uint8List imageBytes, {int maxDimension = 256}) {
  _checkPositive(maxDimension, 'maxDimension');

  final image = decodeImage(imageBytes);
  final longerSide = math.max(image.width, image.height);

  int dstWidth;
  int dstHeight;
  Uint8List pixels;
  if (longerSide <= maxDimension) {
    dstWidth = image.width;
    dstHeight = image.height;
    pixels = image.pixels;
  } else {
    final scale = maxDimension / longerSide;
    dstWidth = math.max(1, (image.width * scale).round());
    dstHeight = math.max(1, (image.height * scale).round());
    pixels = resizePixels(
      image.pixels,
      srcWidth: image.width,
      srcHeight: image.height,
      dstWidth: dstWidth,
      dstHeight: dstHeight,
      channels: image.channels,
    );
  }

  return encodePng(
    pixels,
    width: dstWidth,
    height: dstHeight,
    channels: image.channels,
  );
}

void _checkPositive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}

void _checkChannels(int channels) {
  if (channels < 1 || channels > 4) {
    throw ArgumentError.value(channels, 'channels', 'must be between 1 and 4');
  }
}

void _checkPixelLength(Uint8List pixels, int width, int height, int channels) {
  final expected = width * height * channels;
  if (pixels.length != expected) {
    throw ArgumentError.value(
      pixels.length,
      'pixels.length',
      'must equal width * height * channels ($expected)',
    );
  }
}

/// The off-main-isolate version of [thumbnailJpeg].
///
/// It runs the decode, resize and encode on a background isolate with
/// [Isolate.run], so turning a large photo into a thumbnail doesn't block the
/// calling isolate. In a Flutter app that keeps the UI responsive while a
/// picked image is processed: neither the pure-Dart `image` package nor a plain
/// synchronous FFI call can do that on the main isolate.
///
/// [imageBytes] is copied to the worker isolate and the JPEG is copied back;
/// for a handful of images that copy is small next to the decode itself. See
/// [thumbnailJpeg] for the parameters; an [ImageFfiException] raised in the
/// worker surfaces from the returned future.
Future<Uint8List> thumbnailJpegAsync(
  Uint8List imageBytes, {
  int maxDimension = 256,
  int quality = 85,
}) =>
    Isolate.run(
      () => thumbnailJpeg(
        imageBytes,
        maxDimension: maxDimension,
        quality: quality,
      ),
    );

/// The off-main-isolate version of [thumbnailPng]; see [thumbnailJpegAsync] for
/// how the work is offloaded and [thumbnailPng] for the parameters. Use this
/// when the source has transparency to preserve, since PNG keeps the alpha
/// channel a JPEG thumbnail would drop.
Future<Uint8List> thumbnailPngAsync(
  Uint8List imageBytes, {
  int maxDimension = 256,
}) =>
    Isolate.run(
      () => thumbnailPng(imageBytes, maxDimension: maxDimension),
    );
