import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

/// A 512x512 RGBA image whose top-left quadrant is fully transparent and whose
/// rest is opaque red, encoded to PNG with image_ffi itself.
Uint8List transparentPng() {
  const w = 512;
  const h = 512;
  final px = Uint8List(w * h * 4);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final transparent = x < w ~/ 2 && y < h ~/ 2;
      px[i++] = 200; // r
      px[i++] = 40; // g
      px[i++] = 40; // b
      px[i++] = transparent ? 0 : 255; // a
    }
  }
  return encodePng(px, width: w, height: h, channels: 4);
}

void main() {
  test('thumbnailPng downscales and keeps the alpha channel', () {
    final thumb = thumbnailPng(transparentPng(), maxDimension: 256);
    final decoded = decodeImage(thumb);

    // Scaled to fit the 256 box.
    expect(decoded.width, lessThanOrEqualTo(256));
    expect(decoded.height, lessThanOrEqualTo(256));
    expect(decoded.width, greaterThan(0));

    // Alpha survived; a JPEG thumbnail would have dropped to three channels.
    expect(decoded.channels, 4);

    // A pixel well inside the transparent quadrant is still transparent.
    final tx = decoded.width ~/ 4;
    final ty = decoded.height ~/ 4;
    expect(decoded.pixels[(ty * decoded.width + tx) * 4 + 3], lessThan(40));

    // A pixel in the opaque region is still opaque.
    final ox = decoded.width * 3 ~/ 4;
    final oy = decoded.height * 3 ~/ 4;
    expect(decoded.pixels[(oy * decoded.width + ox) * 4 + 3], greaterThan(200));
  });

  test('an image already within maxDimension keeps its size', () {
    final small =
        encodePng(Uint8List(64 * 64 * 4), width: 64, height: 64, channels: 4);
    final decoded = decodeImage(thumbnailPng(small, maxDimension: 256));
    expect(decoded.width, 64);
    expect(decoded.height, 64);
    expect(decoded.channels, 4);
  });

  test('maxDimension must be positive', () {
    expect(
      () => thumbnailPng(transparentPng(), maxDimension: 0),
      throwsArgumentError,
    );
  });
}
