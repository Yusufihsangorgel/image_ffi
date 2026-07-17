// Compares image_ffi against the pure-Dart `image` package on the common
// decode-then-downscale path. It synthesizes one large PNG, then times both
// libraries decoding it and resizing to a 256px thumbnail, and prints the
// measured medians. Numbers are real and machine-dependent; run it yourself:
//
//   dart run bench/bench.dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_ffi/image_ffi.dart';

const _sourceSize = 2000;
const _thumbSize = 256;
const _warmup = 3;
const _iterations = 15;

/// Runs [action] [_iterations] times after [_warmup] warmups and returns the
/// median wall-clock duration in milliseconds.
double _medianMs(void Function() action) {
  for (var i = 0; i < _warmup; i++) {
    action();
  }
  final samples = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < _iterations; i++) {
    sw
      ..reset()
      ..start();
    action();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2] / 1000.0;
}

void main() {
  // Build a large, non-trivial RGB source image and encode it once as PNG.
  final source = img.Image(width: _sourceSize, height: _sourceSize);
  for (var y = 0; y < _sourceSize; y++) {
    for (var x = 0; x < _sourceSize; x++) {
      source.setPixelRgb(x, y, (x + y) & 0xFF, (x * 3) & 0xFF, (y * 5) & 0xFF);
    }
  }
  final Uint8List png = img.encodePng(source);
  print('source: ${_sourceSize}x$_sourceSize PNG, ${png.length} bytes');
  print('task: decode + resize longer side to ${_thumbSize}px\n');

  final ffiDecodeMs = _medianMs(() {
    decodeImage(png);
  });
  final imageDecodeMs = _medianMs(() {
    img.decodePng(png);
  });

  // Decode once for the resize-only comparison.
  final decoded = decodeImage(png);
  final scale = _thumbSize / _sourceSize;
  final dstW = (decoded.width * scale).round();
  final dstH = (decoded.height * scale).round();
  final oracleImage = img.decodePng(png)!;

  final ffiResizeMs = _medianMs(() {
    resizePixels(
      decoded.pixels,
      srcWidth: decoded.width,
      srcHeight: decoded.height,
      dstWidth: dstW,
      dstHeight: dstH,
      channels: decoded.channels,
    );
  });
  final imageResizeMs = _medianMs(() {
    // Cubic interpolation is the closest quality match to stb's sRGB filter;
    // the default (nearest) would be much faster but far lower quality.
    img.copyResize(
      oracleImage,
      width: dstW,
      height: dstH,
      interpolation: img.Interpolation.cubic,
    );
  });

  final ffiThumbMs = _medianMs(() {
    thumbnailJpeg(png, maxDimension: _thumbSize);
  });
  final imageThumbMs = _medianMs(() {
    final decoded = img.decodePng(png)!;
    final resized = img.copyResize(
      decoded,
      width: dstW,
      height: dstH,
      interpolation: img.Interpolation.cubic,
    );
    img.encodeJpg(resized, quality: 85);
  });

  void row(String op, double ffi, double image) {
    final factor = (image / ffi).toStringAsFixed(1);
    print(
      '${op.padRight(22)} '
      'image_ffi ${ffi.toStringAsFixed(1).padLeft(8)} ms   '
      'image ${image.toStringAsFixed(1).padLeft(8)} ms   '
      '${factor}x',
    );
  }

  row('decode PNG', ffiDecodeMs, imageDecodeMs);
  row('resize to thumbnail', ffiResizeMs, imageResizeMs);
  row('decode+resize+encode', ffiThumbMs, imageThumbMs);
}
