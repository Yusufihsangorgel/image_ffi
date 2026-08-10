// Why a downscaled image comes out darker than it should, and the one
// argument that fixes it.
//
//   dart run example/gamma_correct_resize.dart
//
// `resizePixels` takes a `colorSpace`, it defaults to the right thing, and no
// example touched it. That is a shame, because the bug it avoids is one of the
// most common in image code and it is invisible until you measure: resampling
// sRGB bytes as if they were light makes everything darker.
//
// The test case is a black-and-white checkerboard. Half the pixels are 0 and
// half are 255, so the honest average is *the colour that emits half the
// light*. In sRGB that is about 188, not 128 -- the encoding is a curve, and
// averaging the codes instead of the light lands well below the middle.
//
// Nothing here needs a file: the checkerboard is generated and the numbers
// come out of the resize.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';

/// A black-and-white checkerboard, one byte per pixel.
Uint8List checkerboard(int size) {
  final pixels = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      pixels[y * size + x] = (x + y).isEven ? 255 : 0;
    }
  }
  return pixels;
}

/// sRGB code -> how much light it actually emits, 0..1.
///
/// The curve is not a decoration: it is why averaging codes is wrong. Code 128
/// emits about 22% of the light of 255, not 50%.
double toLight(int code) {
  final c = code / 255;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int meanOf(Uint8List pixels) =>
    (pixels.fold<int>(0, (a, b) => a + b) / pixels.length).round();

void main() {
  const size = 256;
  final board = checkerboard(size);

  // What the board actually emits: half the pixels at full light, half at
  // none, so half the light. The sRGB code for that is what a correct
  // downscale should land on.
  final honest = toLight(255) * 0.5 + toLight(0) * 0.5;
  var expected = 0;
  for (var code = 0; code <= 255; code++) {
    if (toLight(code) >= honest) {
      expected = code;
      break;
    }
  }

  print('');
  print('A ${size}x$size checkerboard: half the pixels 255, half 0.');
  print('It emits half the light of white, which in sRGB is code ~$expected.');
  print('');

  for (final space in ResizeColorSpace.values) {
    final small = resizePixels(
      board,
      srcWidth: size,
      srcHeight: size,
      dstWidth: 1,
      dstHeight: 1,
      channels: 1,
      colorSpace: space,
    );
    final mean = meanOf(small);
    final off = mean - expected;
    print(
      '  ${space.name.padRight(7)} -> $mean'
      '${off == 0 ? '  (right)' : '  ${off > 0 ? '+' : ''}$off from the light-correct value'}',
    );
  }

  print('');
  print('`srgb` is the default and the one you want for photographs and UI:');
  print('it converts to light, resamples, and converts back. `linear` skips');
  print('that, which is correct only when the bytes already are light --');
  print('a mask, a depth map, a channel you keep linear on purpose.');
  print('');
  print('Getting this wrong does not throw and does not look broken in');
  print('isolation. It just makes every thumbnail on the page a little');
  print('darker than the image it came from.');
}
