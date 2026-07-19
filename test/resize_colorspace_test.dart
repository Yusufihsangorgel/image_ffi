import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

void main() {
  group('resizePixels colour handling', () {
    test('2-channel input is grayscale + alpha, not two colour channels', () {
      // 8x1 gray+alpha: left half opaque white, right half transparent black.
      final src = Uint8List(8 * 2);
      for (var x = 0; x < 8; x++) {
        final opaque = x < 4;
        src[x * 2] = opaque ? 255 : 0; // gray
        src[x * 2 + 1] = opaque ? 255 : 0; // alpha
      }
      final out = resizePixels(
        src,
        srcWidth: 8,
        srcHeight: 1,
        dstWidth: 1,
        dstHeight: 1,
        channels: 2,
      );
      // With correct alpha weighting (STBIR_RA) only the opaque white
      // contributes colour, so gray stays near white. The old
      // (stbir_pixel_layout)2 == STBIR_2CHANNEL cast averaged both channels as
      // colour and dragged gray down to ~128.
      expect(
        out[0],
        greaterThan(200),
        reason: 'transparent pixels must not bleed into the colour',
      );
      expect(out[1], closeTo(128, 24), reason: 'alpha is the mean coverage');
    });

    test('colorSpace routes to a different resample: sRGB is brighter', () {
      // 8x1 grayscale, left half black, right half white.
      final src = Uint8List(8);
      for (var x = 0; x < 8; x++) {
        src[x] = x < 4 ? 0 : 255;
      }
      Uint8List run(ResizeColorSpace cs) => resizePixels(
            src,
            srcWidth: 8,
            srcHeight: 1,
            dstWidth: 1,
            dstHeight: 1,
            channels: 1,
            colorSpace: cs,
          );
      final srgb = run(ResizeColorSpace.srgb);
      final linear = run(ResizeColorSpace.linear);
      // sRGB averages in linear light and re-encodes (~188); linear averages
      // the raw bytes (~128). They must differ, proving the flag is wired.
      expect(
        srgb[0],
        greaterThan(linear[0] + 30),
        reason: 'sRGB and linear must take different paths',
      );
      expect(linear[0], closeTo(128, 12));
    });

    test('the sRGB default is unchanged for opaque RGBA', () {
      // A flat colour must survive a downscale on the default path.
      final src = Uint8List(64 * 64 * 4);
      for (var i = 0; i < 64 * 64; i++) {
        src[i * 4] = 200;
        src[i * 4 + 1] = 100;
        src[i * 4 + 2] = 50;
        src[i * 4 + 3] = 255;
      }
      final out = resizePixels(
        src,
        srcWidth: 64,
        srcHeight: 64,
        dstWidth: 16,
        dstHeight: 16,
        channels: 4,
      );
      expect(out.length, 16 * 16 * 4);
      expect(out[0], closeTo(200, 1));
      expect(out[1], closeTo(100, 1));
      expect(out[2], closeTo(50, 1));
      expect(out[3], closeTo(255, 1));
    });
  });
}
