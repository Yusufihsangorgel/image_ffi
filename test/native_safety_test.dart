import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

Uint8List _grayPng({int size = 64}) => encodePng(
  Uint8List(size * size * 3)..fillRange(0, size * size * 3, 120),
  width: size,
  height: size,
  channels: 3,
);

Uint8List _noisePng(int size) {
  final random = math.Random(7);
  final pixels = Uint8List(size * size * 3);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = random.nextInt(256);
  }
  return encodePng(pixels, width: size, height: size, channels: 3);
}

/// What has to hold for a package that hands bytes across an FFI boundary:
/// bad input becomes a Dart error rather than a crash, and the decode/encode
/// round trip does not leak the native buffers it allocates.
void main() {
  group('native safety', () {
    test('undecodable input raises ImageFfiException', () {
      final png = _grayPng();
      for (final entry in {
        'garbage': Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        'truncated': png.sublist(0, 20),
        'header only': png.sublist(0, 8),
      }.entries) {
        expect(
          () => decodeImage(entry.value),
          throwsA(isA<ImageFfiException>()),
          reason: entry.key,
        );
      }
    });

    test('an empty buffer is a bad argument, not a decode failure', () {
      // The README draws this line: invalid image data is an
      // ImageFfiException, a bad argument is an ArgumentError.
      expect(() => decodeImage(Uint8List(0)), throwsArgumentError);
    });

    // RSS is a blunt instrument: mixing decode, resize and encode in one loop
    // makes the Dart heap churn swamp any native leak. Each of the three tests
    // below drives ONE native allocation site in a tight loop, which keeps the
    // measured noise under a megabyte, and each bound is derived from the size
    // of the buffer that site allocates rather than picked by eye.

    test('decodeImage does not leak its native buffers', () {
      final png = _noisePng(192);

      // Two buffers per call: the native copy of the encoded bytes
      // (png.length) and the decoded pixels (192 * 192 * 3). Losing either
      // costs ~158MB over this loop; measured noise is under 1MB.
      const iterations = 1500;
      final smallestLeakMb =
          math.min(png.length, 192 * 192 * 3) * iterations / (1024 * 1024);

      for (var i = 0; i < 200; i++) {
        decodeImage(png);
      }
      final before = ProcessInfo.currentRss;
      for (var i = 0; i < iterations; i++) {
        decodeImage(png);
      }
      final grownMb = (ProcessInfo.currentRss - before) / (1024 * 1024);

      expect(
        smallestLeakMb,
        greaterThan(100),
        reason: 'payload too small to detect a leak',
      );
      expect(
        grownMb,
        lessThan(20),
        reason:
            'grew ${grownMb}MB over $iterations decodes; '
            'the smallest leak this loop can spring is ${smallestLeakMb}MB',
      );
    });

    test('resizePixels does not leak its native output buffer', () {
      final decoded = decodeImage(_noisePng(192));

      // 160 * 160 * 3 bytes of output per call, ~110MB across the loop.
      const iterations = 1500;
      final leakMb = 160 * 160 * 3 * iterations / (1024 * 1024);

      Uint8List cycle() => resizePixels(
        decoded.pixels,
        srcWidth: decoded.width,
        srcHeight: decoded.height,
        dstWidth: 160,
        dstHeight: 160,
        channels: decoded.channels,
      );

      for (var i = 0; i < 200; i++) {
        cycle();
      }
      final before = ProcessInfo.currentRss;
      for (var i = 0; i < iterations; i++) {
        cycle();
      }
      final grownMb = (ProcessInfo.currentRss - before) / (1024 * 1024);

      expect(
        leakMb,
        greaterThan(100),
        reason: 'payload too small to detect a leak',
      );
      expect(
        grownMb,
        lessThan(20),
        reason:
            'grew ${grownMb}MB over $iterations resizes; '
            'a lost free would cost ${leakMb}MB',
      );
    });

    test('encodeJpeg does not leak its native output buffer', () {
      final decoded = decodeImage(_noisePng(192));
      final small = resizePixels(
        decoded.pixels,
        srcWidth: decoded.width,
        srcHeight: decoded.height,
        dstWidth: 160,
        dstHeight: 160,
        channels: decoded.channels,
      );

      // The encoded JPEG is the smallest of the buffers here, which is why the
      // noise band matters: ~19KB per call, so the loop has to be long enough
      // for a lost free to clear it by an order of magnitude.
      const iterations = 1500;

      for (var i = 0; i < 200; i++) {
        encodeJpeg(small, width: 160, height: 160, channels: 3);
      }
      final before = ProcessInfo.currentRss;
      var encodedBytes = 0;
      for (var i = 0; i < iterations; i++) {
        encodedBytes = encodeJpeg(
          small,
          width: 160,
          height: 160,
          channels: 3,
        ).length;
      }
      final grownMb = (ProcessInfo.currentRss - before) / (1024 * 1024);
      final leakMb = encodedBytes * iterations / (1024 * 1024);

      expect(
        leakMb,
        greaterThan(20),
        reason: 'payload too small to detect a leak',
      );
      expect(
        grownMb,
        lessThan(10),
        reason:
            'grew ${grownMb}MB over $iterations encodes; '
            'a lost free would cost ${leakMb}MB',
      );
    });

    test('thumbnailJpeg bounds the longer side and never enlarges', () {
      final png = _grayPng();
      final thumb = imageInfo(thumbnailJpeg(png, maxDimension: 16));
      expect(thumb.width, lessThanOrEqualTo(16));
      expect(thumb.height, lessThanOrEqualTo(16));

      // Already inside the bound: re-encoded, not scaled up.
      final small = imageInfo(
        thumbnailJpeg(_grayPng(size: 8), maxDimension: 64),
      );
      expect(small.width, 8);
      expect(small.height, 8);
    });

    test('a non-positive resize target is rejected', () {
      final decoded = decodeImage(_grayPng());
      for (final target in [0, -1]) {
        expect(
          () => resizePixels(
            decoded.pixels,
            srcWidth: decoded.width,
            srcHeight: decoded.height,
            dstWidth: target,
            dstHeight: 8,
            channels: decoded.channels,
          ),
          throwsArgumentError,
          reason: 'dstWidth $target',
        );
      }
    });
  });
}
