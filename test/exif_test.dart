import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

/// Wraps [jpeg] with an APP1 EXIF segment carrying [orientation].
///
/// Phone photos arrive this way: the pixels are the sensor's, and the tag
/// says how the phone was held.
Uint8List withExifOrientation(Uint8List jpeg, int orientation) {
  final tiff = BytesBuilder()
    ..add([0x49, 0x49]) // 'II', little-endian
    ..add([42, 0]) // the TIFF magic
    ..add([8, 0, 0, 0]) // IFD0 begins right after this header
    ..add([1, 0]); // one entry
  final entry = ByteData(12)
    ..setUint16(0, 0x0112, Endian.little) // Orientation
    ..setUint16(2, 3, Endian.little) // SHORT
    ..setUint32(4, 1, Endian.little) // count
    ..setUint16(8, orientation, Endian.little); // value, stored inline
  tiff.add(entry.buffer.asUint8List());
  tiff.add([0, 0, 0, 0]); // no next IFD

  final payload =
      (BytesBuilder()
            ..add('Exif'.codeUnits)
            ..add([0, 0])
            ..add(tiff.toBytes()))
          .toBytes();
  final length = payload.length + 2;
  return Uint8List.fromList([
    jpeg[0], jpeg[1], // SOI
    0xFF, 0xE1, (length >> 8) & 0xFF, length & 0xFF,
    ...payload,
    ...jpeg.sublist(2),
  ]);
}

/// A landscape image, white on the left half and black on the right, so a
/// transform is visible in the pixels and not only in the dimensions.
Uint8List landscapeJpeg({int width = 40, int height = 20}) {
  final pixels = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = x < width ~/ 2 ? 255 : 0;
      final i = (y * width + x) * 3;
      pixels[i] = pixels[i + 1] = pixels[i + 2] = value;
    }
  }
  return encodeJpeg(
    pixels,
    width: width,
    height: height,
    channels: 3,
    quality: 95,
  );
}

void main() {
  group('exifOrientation', () {
    test('reads the tag a phone camera writes', () {
      final jpeg = landscapeJpeg();
      expect(exifOrientation(jpeg), 1, reason: 'no EXIF means upright');
      for (final value in [2, 3, 4, 5, 6, 7, 8]) {
        expect(exifOrientation(withExifOrientation(jpeg, value)), value);
      }
    });

    test('returns 1 rather than failing on input it cannot read', () {
      // A malformed tag must never take down a decode that would otherwise
      // succeed; the worst case is the image staying as it was.
      expect(exifOrientation(Uint8List.fromList([1, 2, 3])), 1);
      expect(exifOrientation(Uint8List(0)), 1);
      // PNG: no orientation concept at all.
      expect(exifOrientation(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), 1);
      // A JPEG whose EXIF claims an out-of-range value.
      expect(exifOrientation(withExifOrientation(landscapeJpeg(), 99)), 1);
    });
  });

  group('applyExifOrientation', () {
    test('swaps the axes for the four rotating values', () {
      final image = decodeImage(landscapeJpeg());
      expect(image.width, 40);
      expect(image.height, 20);

      for (final orientation in [5, 6, 7, 8]) {
        final turned = applyExifOrientation(image, orientation);
        expect(turned.width, 20, reason: 'orientation $orientation');
        expect(turned.height, 40, reason: 'orientation $orientation');
      }
      for (final orientation in [1, 2, 3, 4]) {
        final flat = applyExifOrientation(image, orientation);
        expect(flat.width, 40, reason: 'orientation $orientation');
        expect(flat.height, 20, reason: 'orientation $orientation');
      }
    });

    test('mirroring moves the light half to the other side', () {
      final image = decodeImage(landscapeJpeg());
      int leftPixel(DecodedImage img) => img.pixels[0];
      // Orientation 2 is a horizontal mirror: the white left half becomes the
      // right half, so the first pixel goes dark.
      expect(leftPixel(image), greaterThan(200));
      expect(leftPixel(applyExifOrientation(image, 2)), lessThan(60));
    });

    test('leaves the image alone for 1 and for a value out of range', () {
      final image = decodeImage(landscapeJpeg());
      expect(identical(applyExifOrientation(image, 1), image), isTrue);
      expect(identical(applyExifOrientation(image, 0), image), isTrue);
      expect(identical(applyExifOrientation(image, 9), image), isTrue);
    });
  });

  group('thumbnails', () {
    test('a portrait phone photo comes out upright', () {
      // The sensor buffer is landscape and the tag says the phone was turned;
      // without reading it the thumbnail was sideways, with no error to say so.
      final sideways = withExifOrientation(landscapeJpeg(), 6);
      final thumbnail = decodeImage(thumbnailJpeg(sideways, maxDimension: 100));
      expect(thumbnail.height, greaterThan(thumbnail.width));
    });

    test('applyOrientation: false keeps the raw sensor framing', () {
      final sideways = withExifOrientation(landscapeJpeg(), 6);
      final raw = decodeImage(
        thumbnailJpeg(sideways, maxDimension: 100, applyOrientation: false),
      );
      expect(raw.width, greaterThan(raw.height));
    });

    test('thumbnailPng honours the tag too', () {
      final sideways = withExifOrientation(landscapeJpeg(), 6);
      final thumbnail = decodeImage(thumbnailPng(sideways, maxDimension: 100));
      expect(thumbnail.height, greaterThan(thumbnail.width));
    });
  });
}
