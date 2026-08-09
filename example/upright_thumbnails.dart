// A phone photo decodes sideways, and the thumbnail comes out upright anyway.
//
// Hold a phone in portrait and the sensor still records a landscape buffer.
// What makes the photo upright is a number in the file's EXIF header saying
// how to turn it. Viewers read that number; code that decodes pixels does not,
// unless someone taught it to.
//
// Run it with:
//   dart run example/upright_thumbnails.dart

import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';

void main() {
  final photo = _portraitPhoneShot();

  print(
    'EXIF orientation tag       ${exifOrientation(photo)}  (6: turn 90 CW)',
  );

  final sensor = decodeImage(photo);
  print('decodeImage                ${_size(sensor)}  the sensor buffer');

  final thumb = decodeImage(thumbnailJpeg(photo, maxDimension: 128));
  print(
    'thumbnailJpeg              ${_size(thumb)}  upright, nothing asked for',
  );

  final raw = decodeImage(
    thumbnailJpeg(photo, maxDimension: 128, applyOrientation: false),
  );
  print('  ...applyOrientation off  ${_size(raw)}  the sideways version');

  // Reading and applying the tag by hand, for a pipeline that does its own
  // decoding and resizing.
  final upright = applyExifOrientation(sensor, exifOrientation(photo));
  print('applyExifOrientation       ${_size(upright)}  same result, by hand');
}

String _size(DecodedImage i) => '${i.width}x${i.height}'.padRight(9);

/// A 400x300 sensor buffer tagged the way a phone tags a portrait shot.
Uint8List _portraitPhoneShot() {
  final pixels = Uint8List(400 * 300 * 3);
  for (var y = 0; y < 300; y++) {
    for (var x = 0; x < 400; x++) {
      final i = (y * 400 + x) * 3;
      // A gradient, so a rotation is visible rather than a flat colour.
      pixels[i] = (x * 255 ~/ 400);
      pixels[i + 1] = (y * 255 ~/ 300);
      pixels[i + 2] = 90;
    }
  }
  final jpeg = encodeJpeg(pixels, width: 400, height: 300, channels: 3);
  return _withExifOrientation(jpeg, 6);
}

/// Wraps [jpeg] in the APP1 EXIF segment a camera writes.
Uint8List _withExifOrientation(Uint8List jpeg, int orientation) {
  final tiff = BytesBuilder()
    ..add([0x49, 0x49]) // 'II', little-endian
    ..add([42, 0]) // TIFF magic
    ..add([8, 0, 0, 0]) // IFD0 starts after this header
    ..add([1, 0]); // one entry
  final entry = ByteData(12)
    ..setUint16(0, 0x0112, Endian.little) // Orientation
    ..setUint16(2, 3, Endian.little) // SHORT
    ..setUint32(4, 1, Endian.little) // count
    ..setUint16(8, orientation, Endian.little); // value, stored inline
  tiff
    ..add(entry.buffer.asUint8List())
    ..add([0, 0, 0, 0]); // no next IFD

  final payload =
      (BytesBuilder()
            ..add('Exif'.codeUnits)
            ..add([0, 0])
            ..add(tiff.toBytes()))
          .toBytes();
  final length = payload.length + 2;
  return Uint8List.fromList([
    ...jpeg.sublist(0, 2), // SOI
    0xFF, 0xE1, (length >> 8) & 0xFF, length & 0xFF,
    ...payload,
    ...jpeg.sublist(2),
  ]);
}
