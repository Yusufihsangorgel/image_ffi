import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

/// Builds a known RGBA bitmap with per-pixel varying colour and alpha, so a
/// PNG encoded from it stays four-channel and every pixel is distinct enough
/// to catch row-order or channel-order mistakes.
Uint8List buildRgba(int width, int height) {
  final bytes = Uint8List(width * height * 4);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[i++] = (x * 7 + y * 3) & 0xFF;
      bytes[i++] = (x * 3 + y * 11) & 0xFF;
      bytes[i++] = (x + y * 5) & 0xFF;
      bytes[i++] = 255 - ((x + y) & 0x3F);
    }
  }
  return bytes;
}

/// Builds a known RGB bitmap (no alpha).
Uint8List buildRgb(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  var i = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[i++] = (x * 5 + y) & 0xFF;
      bytes[i++] = (x + y * 7) & 0xFF;
      bytes[i++] = (x * 2 + y * 2) & 0xFF;
    }
  }
  return bytes;
}

/// Builds a solid-colour RGBA bitmap.
Uint8List buildFlat(int width, int height, int r, int g, int b, int a) {
  final bytes = Uint8List(width * height * 4);
  for (var p = 0; p < width * height; p++) {
    bytes[p * 4] = r;
    bytes[p * 4 + 1] = g;
    bytes[p * 4 + 2] = b;
    bytes[p * 4 + 3] = a;
  }
  return bytes;
}

/// Encodes raw pixels as a PNG using the `image` oracle so decoders under test
/// are fed a real, independently produced file.
Uint8List oraclePng(Uint8List pixels, int width, int height, int channels) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    numChannels: channels,
  );
  return img.encodePng(image);
}

/// Encodes raw RGB pixels as a JPEG using the `image` oracle.
Uint8List oracleJpg(Uint8List pixels, int width, int height) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    numChannels: 3,
  );
  return img.encodeJpg(image, quality: 95);
}

void main() {
  group('decodeImage', () {
    test('reports the dimensions and channel count of an RGBA PNG', () {
      final png = oraclePng(buildRgba(16, 12), 16, 12, 4);
      final decoded = decodeImage(png);
      expect(decoded.width, 16);
      expect(decoded.height, 12);
      expect(decoded.channels, 4);
      expect(decoded.pixels.length, 16 * 12 * 4);
    });

    test('reproduces the RGBA pixels exactly (PNG is lossless)', () {
      final original = buildRgba(20, 14);
      final png = oraclePng(original, 20, 14, 4);
      final decoded = decodeImage(png);
      expect(decoded.pixels, equals(original));
    });

    test('reproduces the RGB pixels exactly for a three-channel PNG', () {
      final original = buildRgb(18, 9);
      final png = oraclePng(original, 18, 9, 3);
      final decoded = decodeImage(png);
      expect(decoded.channels, 3);
      expect(decoded.pixels, equals(original));
    });

    test(
      'forceChannels: 4 promotes an RGB image to RGBA with opaque alpha',
      () {
        final original = buildRgb(8, 8);
        final png = oraclePng(original, 8, 8, 3);
        final decoded = decodeImage(png, forceChannels: 4);
        expect(decoded.channels, 4);
        for (var p = 0; p < 8 * 8; p++) {
          expect(decoded.pixels[p * 4], original[p * 3]);
          expect(decoded.pixels[p * 4 + 1], original[p * 3 + 1]);
          expect(decoded.pixels[p * 4 + 2], original[p * 3 + 2]);
          expect(decoded.pixels[p * 4 + 3], 255);
        }
      },
    );

    test('forceChannels: 3 drops alpha and keeps RGB unchanged', () {
      final original = buildRgba(8, 8);
      final png = oraclePng(original, 8, 8, 4);
      final decoded = decodeImage(png, forceChannels: 3);
      expect(decoded.channels, 3);
      for (var p = 0; p < 8 * 8; p++) {
        expect(decoded.pixels[p * 3], original[p * 4]);
        expect(decoded.pixels[p * 3 + 1], original[p * 4 + 1]);
        expect(decoded.pixels[p * 3 + 2], original[p * 4 + 2]);
      }
    });

    test('decodes a JPEG to three channels with matching dimensions', () {
      final jpg = oracleJpg(buildRgb(24, 16), 24, 16);
      final decoded = decodeImage(jpg);
      expect(decoded.width, 24);
      expect(decoded.height, 16);
      expect(decoded.channels, 3);
    });

    test('throws ImageFfiException on bytes that are not an image', () {
      final garbage = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(() => decodeImage(garbage), throwsA(isA<ImageFfiException>()));
    });

    test('throws ArgumentError on empty input', () {
      expect(() => decodeImage(Uint8List(0)), throwsArgumentError);
    });

    test('throws ArgumentError on an out-of-range forceChannels', () {
      final png = oraclePng(buildRgba(4, 4), 4, 4, 4);
      expect(() => decodeImage(png, forceChannels: 0), throwsArgumentError);
      expect(() => decodeImage(png, forceChannels: 5), throwsArgumentError);
    });
  });

  group('imageInfo', () {
    test('matches a full decode for a PNG', () {
      final png = oraclePng(buildRgba(30, 21), 30, 21, 4);
      final info = imageInfo(png);
      final decoded = decodeImage(png);
      expect(info.width, decoded.width);
      expect(info.height, decoded.height);
      expect(info.channels, decoded.channels);
      expect(info.width, 30);
      expect(info.height, 21);
    });

    test('returns the dimensions of a JPEG', () {
      final jpg = oracleJpg(buildRgb(40, 25), 40, 25);
      final info = imageInfo(jpg);
      expect(info.width, 40);
      expect(info.height, 25);
    });

    test('throws ArgumentError on empty input', () {
      expect(() => imageInfo(Uint8List(0)), throwsArgumentError);
    });

    test('throws ImageFfiException on unparseable bytes', () {
      final garbage = Uint8List.fromList(List<int>.filled(16, 0x42));
      expect(() => imageInfo(garbage), throwsA(isA<ImageFfiException>()));
    });
  });

  group('resizePixels', () {
    test('downscales to the requested dimensions', () {
      final pixels = buildRgba(100, 50);
      final resized = resizePixels(
        pixels,
        srcWidth: 100,
        srcHeight: 50,
        dstWidth: 40,
        dstHeight: 20,
        channels: 4,
      );
      expect(resized.length, 40 * 20 * 4);
    });

    test('upscales to the requested dimensions', () {
      final pixels = buildRgba(10, 10);
      final resized = resizePixels(
        pixels,
        srcWidth: 10,
        srcHeight: 10,
        dstWidth: 20,
        dstHeight: 20,
        channels: 4,
      );
      expect(resized.length, 20 * 20 * 4);
    });

    test('keeps a flat colour flat after resizing', () {
      final pixels = buildFlat(64, 64, 200, 100, 50, 255);
      final resized = resizePixels(
        pixels,
        srcWidth: 64,
        srcHeight: 64,
        dstWidth: 16,
        dstHeight: 16,
        channels: 4,
      );
      expect(resized.length, 16 * 16 * 4);
      for (var p = 0; p < 16 * 16; p++) {
        expect(resized[p * 4], closeTo(200, 1));
        expect(resized[p * 4 + 1], closeTo(100, 1));
        expect(resized[p * 4 + 2], closeTo(50, 1));
        expect(resized[p * 4 + 3], closeTo(255, 1));
      }
    });

    test('throws ArgumentError when pixels length does not match', () {
      final pixels = buildRgba(10, 10);
      expect(
        () => resizePixels(
          pixels,
          srcWidth: 10,
          srcHeight: 11,
          dstWidth: 5,
          dstHeight: 5,
          channels: 4,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on a non-positive dimension', () {
      final pixels = buildRgba(10, 10);
      expect(
        () => resizePixels(
          pixels,
          srcWidth: 10,
          srcHeight: 10,
          dstWidth: 0,
          dstHeight: 5,
          channels: 4,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on an out-of-range channel count', () {
      final pixels = Uint8List(10 * 10 * 5);
      expect(
        () => resizePixels(
          pixels,
          srcWidth: 10,
          srcHeight: 10,
          dstWidth: 5,
          dstHeight: 5,
          channels: 5,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when dstWidth exceeds the native Int32 range '
        'instead of silently truncating at the FFI boundary', () {
      final pixels = buildRgba(4, 4);
      // 2^32 + 100: an Int32 parameter marshals this down to 100, which
      // used to make the native side allocate and fill a buffer for
      // dstWidth=100 while the Dart side sized its asTypedList() view from
      // the untruncated 4294967396, producing a huge out-of-bounds view
      // over a tiny allocation.
      expect(
        () => resizePixels(
          pixels,
          srcWidth: 4,
          srcHeight: 4,
          dstWidth: 4294967396,
          dstHeight: 10,
          channels: 1,
        ),
        throwsArgumentError,
      );
    });

    test(
      'throws ArgumentError when dstHeight exceeds the native Int32 range',
      () {
        final pixels = buildRgba(4, 4);
        expect(
          () => resizePixels(
            pixels,
            srcWidth: 4,
            srcHeight: 4,
            dstWidth: 10,
            dstHeight: 4294967396,
            channels: 1,
          ),
          throwsArgumentError,
        );
      },
    );

    test('throws ArgumentError when srcWidth or srcHeight exceeds the native '
        'Int32 range', () {
      final pixels = buildRgba(4, 4);
      expect(
        () => resizePixels(
          pixels,
          srcWidth: 4294967396,
          srcHeight: 4,
          dstWidth: 4,
          dstHeight: 4,
          channels: 4,
        ),
        throwsArgumentError,
      );
      expect(
        () => resizePixels(
          pixels,
          srcWidth: 4,
          srcHeight: 4294967396,
          dstWidth: 4,
          dstHeight: 4,
          channels: 4,
        ),
        throwsArgumentError,
      );
    });
  });

  group('encodeJpeg', () {
    test('round-trips within a small mean error (JPEG is lossy)', () {
      const width = 48;
      const height = 32;
      final original = buildRgb(width, height);
      final jpg = encodeJpeg(
        original,
        width: width,
        height: height,
        channels: 3,
        quality: 90,
      );
      final decoded = img.decodeJpg(jpg)!;
      expect(decoded.width, width);
      expect(decoded.height, height);

      var totalError = 0;
      var i = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final p = decoded.getPixel(x, y);
          totalError += (p.r.toInt() - original[i++]).abs();
          totalError += (p.g.toInt() - original[i++]).abs();
          totalError += (p.b.toInt() - original[i++]).abs();
        }
      }
      final meanError = totalError / (width * height * 3);
      expect(meanError, lessThan(12));
    });

    test('throws ArgumentError on an out-of-range quality', () {
      final pixels = buildRgb(4, 4);
      expect(
        () => encodeJpeg(pixels, width: 4, height: 4, channels: 3, quality: 0),
        throwsArgumentError,
      );
      expect(
        () =>
            encodeJpeg(pixels, width: 4, height: 4, channels: 3, quality: 101),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when pixels length does not match', () {
      final pixels = buildRgb(4, 4);
      expect(
        () => encodeJpeg(pixels, width: 5, height: 4, channels: 3),
        throwsArgumentError,
      );
    });
  });

  group('encodePng', () {
    test('round-trips exactly through the oracle (PNG is lossless)', () {
      const width = 24;
      const height = 18;
      final original = buildRgba(width, height);
      final png = encodePng(
        original,
        width: width,
        height: height,
        channels: 4,
      );
      final decoded = img.decodePng(png)!;
      expect(decoded.width, width);
      expect(decoded.height, height);
      var i = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final p = decoded.getPixel(x, y);
          expect(p.r.toInt(), original[i++]);
          expect(p.g.toInt(), original[i++]);
          expect(p.b.toInt(), original[i++]);
          expect(p.a.toInt(), original[i++]);
        }
      }
    });

    test('is decodable again by image_ffi with identical pixels', () {
      const width = 12;
      const height = 12;
      final original = buildRgba(width, height);
      final png = encodePng(
        original,
        width: width,
        height: height,
        channels: 4,
      );
      final decoded = decodeImage(png);
      expect(decoded.pixels, equals(original));
    });

    test('throws ArgumentError on a non-positive dimension', () {
      final pixels = buildRgba(4, 4);
      expect(
        () => encodePng(pixels, width: 0, height: 4, channels: 4),
        throwsArgumentError,
      );
    });
  });

  group('thumbnailJpeg', () {
    test('downscales a landscape image so the longer side fits', () {
      final png = oraclePng(buildRgb(1000, 500), 1000, 500, 3);
      final thumb = thumbnailJpeg(png, maxDimension: 256);
      final decoded = img.decodeJpg(thumb)!;
      expect(decoded.width, 256);
      expect(decoded.height, 128);
    });

    test('downscales a portrait image so the longer side fits', () {
      final png = oraclePng(buildRgb(500, 1000), 500, 1000, 3);
      final thumb = thumbnailJpeg(png, maxDimension: 256);
      final decoded = img.decodeJpg(thumb)!;
      expect(decoded.width, 128);
      expect(decoded.height, 256);
    });

    test('does not enlarge an image already within the bound', () {
      final png = oraclePng(buildRgb(10, 10), 10, 10, 3);
      final thumb = thumbnailJpeg(png, maxDimension: 256);
      final decoded = img.decodeJpg(thumb)!;
      expect(decoded.width, 10);
      expect(decoded.height, 10);
    });

    test('handles a four-channel source by dropping alpha', () {
      final png = oraclePng(buildRgba(400, 300), 400, 300, 4);
      final thumb = thumbnailJpeg(png, maxDimension: 100);
      final decoded = img.decodeJpg(thumb)!;
      expect(decoded.width, 100);
      expect(decoded.height, 75);
    });

    test('throws ArgumentError on a non-positive maxDimension', () {
      final png = oraclePng(buildRgb(10, 10), 10, 10, 3);
      expect(() => thumbnailJpeg(png, maxDimension: 0), throwsArgumentError);
    });

    test('throws ArgumentError on an out-of-range quality', () {
      final png = oraclePng(buildRgb(10, 10), 10, 10, 3);
      expect(() => thumbnailJpeg(png, quality: 200), throwsArgumentError);
    });

    test('throws ImageFfiException when the input is not an image', () {
      final garbage = Uint8List.fromList(List<int>.filled(20, 9));
      expect(() => thumbnailJpeg(garbage), throwsA(isA<ImageFfiException>()));
    });
  });
}
