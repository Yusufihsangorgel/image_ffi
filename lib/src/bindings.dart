import 'dart:ffi';

import 'package:ffi/ffi.dart';

// Bindings to the C ABI shim over the vendored stb libraries. The native
// library is produced by hook/build.dart, which registers it under the asset
// id of this file (src/bindings.dart), so every @Native symbol below resolves
// to it. Native heap memory goes through the portable package:ffi allocator
// rather than a direct @Native binding to malloc/free, because DynamicLibrary
// symbol lookup for the C runtime does not resolve on Windows.

/// Decodes an encoded image from memory.
///
/// On success returns a heap buffer of `outW * outH * outChannels` bytes and
/// writes the dimensions and channel count through the out pointers; returns
/// [nullptr] on failure. Free the result with [imgffiFreeImage].
@Native<
  Pointer<Uint8> Function(
    Pointer<Uint8>,
    Int,
    Int,
    Pointer<Int>,
    Pointer<Int>,
    Pointer<Int>,
  )
>(symbol: 'imgffi_decode')
external Pointer<Uint8> imgffiDecode(
  Pointer<Uint8> data,
  int len,
  int forceChannels,
  Pointer<Int> outWidth,
  Pointer<Int> outHeight,
  Pointer<Int> outChannels,
);

/// Frees a buffer returned by [imgffiDecode].
@Native<Void Function(Pointer<Uint8>)>(symbol: 'imgffi_free_image')
external void imgffiFreeImage(Pointer<Uint8> pixels);

/// Reads width, height and channel count without decoding the pixels. Returns
/// 1 on success and 0 if the header could not be parsed.
@Native<
  Int Function(Pointer<Uint8>, Int, Pointer<Int>, Pointer<Int>, Pointer<Int>)
>(symbol: 'imgffi_info')
external int imgffiInfo(
  Pointer<Uint8> data,
  int len,
  Pointer<Int> outWidth,
  Pointer<Int> outHeight,
  Pointer<Int> outChannels,
);

/// High-quality resize. `linear` is 0 for an sRGB-correct resample and 1 for a
/// linear one. Returns a heap buffer of `dstWidth * dstHeight * channels`
/// bytes, or [nullptr] on failure. Free the result with [imgffiFreeBuffer].
@Native<Pointer<Uint8> Function(Pointer<Uint8>, Int, Int, Int, Int, Int, Int)>(
  symbol: 'imgffi_resize',
)
external Pointer<Uint8> imgffiResize(
  Pointer<Uint8> input,
  int srcWidth,
  int srcHeight,
  int dstWidth,
  int dstHeight,
  int channels,
  int linear,
);

/// Encodes pixels as a PNG into memory. Returns a heap buffer of `*outLen`
/// bytes, or [nullptr] on failure. Free the result with [imgffiFreeBuffer].
@Native<Pointer<Uint8> Function(Pointer<Uint8>, Int, Int, Int, Pointer<Int>)>(
  symbol: 'imgffi_encode_png',
)
external Pointer<Uint8> imgffiEncodePng(
  Pointer<Uint8> pixels,
  int width,
  int height,
  int channels,
  Pointer<Int> outLen,
);

/// Encodes pixels as a JPEG into memory at the given quality. Returns a heap
/// buffer of `*outLen` bytes, or [nullptr] on failure. Free the result with
/// [imgffiFreeBuffer].
@Native<
  Pointer<Uint8> Function(Pointer<Uint8>, Int, Int, Int, Int, Pointer<Int>)
>(symbol: 'imgffi_encode_jpg')
external Pointer<Uint8> imgffiEncodeJpg(
  Pointer<Uint8> pixels,
  int width,
  int height,
  int channels,
  int quality,
  Pointer<Int> outLen,
);

/// Frees a buffer returned by [imgffiResize], [imgffiEncodePng] or
/// [imgffiEncodeJpg].
@Native<Void Function(Pointer<Uint8>)>(symbol: 'imgffi_free_buffer')
external void imgffiFreeBuffer(Pointer<Uint8> buffer);

/// stb's most recent failure reason, or [nullptr] if none is available. The
/// string is owned by stb and must not be freed.
@Native<Pointer<Utf8> Function()>(symbol: 'imgffi_failure_reason')
external Pointer<Utf8> imgffiFailureReason();

/// Allocates [bytes] bytes of native heap memory. `malloc(0)` may legally
/// return null, so a zero request is rounded up to one byte.
Pointer<Uint8> allocateBytes(int bytes) =>
    malloc.allocate<Uint8>(bytes < 1 ? 1 : bytes);

/// Frees native memory allocated by [allocateBytes].
void freeBytes(Pointer<Uint8> pointer) => malloc.free(pointer);
