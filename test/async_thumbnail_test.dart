import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

/// A synthetic RGB JPEG with a gradient, decodable by the thumbnail functions.
Uint8List syntheticJpeg(int width, int height) {
  final px = Uint8List(width * height * 3);
  for (var i = 0; i < px.length; i += 3) {
    px[i] = (i ~/ 3) % 256; // r gradient
    px[i + 1] = 100;
    px[i + 2] = 200;
  }
  return encodeJpeg(px, width: width, height: height, channels: 3);
}

/// A synthetic RGBA PNG with a gradient and a constant alpha.
Uint8List syntheticPng(int width, int height) {
  final px = Uint8List(width * height * 4);
  for (var i = 0; i < px.length; i += 4) {
    px[i] = (i ~/ 4) % 256;
    px[i + 1] = 50;
    px[i + 2] = 150;
    px[i + 3] = 255;
  }
  return encodePng(px, width: width, height: height, channels: 4);
}

void main() {
  test('thumbnailJpegAsync returns the same bytes as thumbnailJpeg', () async {
    final src = syntheticJpeg(300, 200);
    final expected = thumbnailJpeg(src, maxDimension: 64, quality: 80);
    final actual = await thumbnailJpegAsync(src, maxDimension: 64, quality: 80);
    // The async path is the same native operation on a background isolate, so
    // the output must be byte-for-byte identical to the synchronous call.
    expect(actual, expected);
  });

  test('thumbnailPngAsync returns the same bytes as thumbnailPng', () async {
    final src = syntheticPng(300, 200);
    final expected = thumbnailPng(src, maxDimension: 64);
    final actual = await thumbnailPngAsync(src, maxDimension: 64);
    expect(actual, expected);
  });

  test('an error in the worker isolate surfaces from the future', () {
    final notAnImage = Uint8List.fromList([1, 2, 3, 4, 5]);
    expect(
      () => thumbnailJpegAsync(notAnImage),
      throwsA(isA<ImageFfiException>()),
    );
  });
}
