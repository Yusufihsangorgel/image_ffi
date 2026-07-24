import 'dart:io';
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

Uint8List _grayPng({int size = 64}) => encodePng(
  Uint8List(size * size * 3)..fillRange(0, size * size * 3, 120),
  width: size,
  height: size,
  channels: 3,
);

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

    test('decode, resize and encode in a loop does not leak', () {
      final png = _grayPng();

      Uint8List cycle() {
        final decoded = decodeImage(png);
        final small = resizePixels(
          decoded.pixels,
          srcWidth: decoded.width,
          srcHeight: decoded.height,
          dstWidth: 32,
          dstHeight: 32,
          channels: decoded.channels,
        );
        return encodeJpeg(
          small,
          width: 32,
          height: 32,
          channels: decoded.channels,
        );
      }

      // Warm up so first-call allocations are not counted as growth.
      for (var i = 0; i < 100; i++) {
        cycle();
      }

      final before = ProcessInfo.currentRss;
      for (var i = 0; i < 2000; i++) {
        cycle();
      }
      final grownMb = (ProcessInfo.currentRss - before) / (1024 * 1024);

      // Each cycle allocates and frees several native buffers; leaking any of
      // them would cost hundreds of megabytes across 2000 iterations.
      expect(
        grownMb,
        lessThan(50),
        reason: 'grew ${grownMb}MB over 2000 cycles',
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
