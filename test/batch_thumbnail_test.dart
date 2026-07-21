import 'dart:async';
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
// The concurrency bound lives in an internal combinator; import the source
// library directly to exercise it with an instrumented work function.
import 'package:image_ffi/src/image_ffi_base.dart' show mapBounded;
import 'package:test/test.dart';

/// A synthetic RGB JPEG with a gradient, decodable by the thumbnail functions.
Uint8List syntheticJpeg(int width, int height) {
  final px = Uint8List(width * height * 3);
  for (var i = 0; i < px.length; i += 3) {
    px[i] = (i ~/ 3) % 256;
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
  test('thumbnailJpegBatch yields one valid thumbnail per input', () async {
    final images = [
      syntheticJpeg(300, 200),
      syntheticJpeg(200, 300),
      syntheticJpeg(150, 150),
      syntheticJpeg(400, 100),
      syntheticJpeg(120, 340),
    ];

    final thumbs =
        await thumbnailJpegBatch(images, maxDimension: 64, concurrency: 2)
            .toList();

    expect(thumbs, hasLength(images.length));
    for (final thumb in thumbs) {
      expect(thumb, isNotEmpty);
      // Each output must be a real encoded image the package can read back.
      final info = imageInfo(thumb);
      expect(info.width, lessThanOrEqualTo(64));
      expect(info.height, lessThanOrEqualTo(64));
    }
  });

  test('thumbnailPngBatch yields one valid thumbnail per input', () async {
    final images = [
      syntheticPng(300, 200),
      syntheticPng(200, 300),
      syntheticPng(150, 150),
    ];

    final thumbs =
        await thumbnailPngBatch(images, maxDimension: 48, concurrency: 2)
            .toList();

    expect(thumbs, hasLength(images.length));
    for (final thumb in thumbs) {
      expect(thumb, isNotEmpty);
      final decoded = decodeImage(thumb);
      expect(decoded.width, lessThanOrEqualTo(48));
      expect(decoded.height, lessThanOrEqualTo(48));
    }
  });

  test('mapBounded never runs more than concurrency work calls at once',
      () async {
    var inFlight = 0;
    var peak = 0;
    // Each work call must wait to be released, so several sit ready at once and
    // the semaphore is the only thing keeping the count down.
    final gates = List.generate(8, (_) => Completer<void>());

    final results = mapBounded<int, int>(
      List.generate(8, (i) => i),
      2,
      (i) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await gates[i].future;
        inFlight--;
        return i * 10;
      },
    );

    final collected = <int>[];
    final done = results.listen(collected.add).asFuture<void>();

    // Let the started work calls register, then release them one at a time so
    // the pool only ever refills up to the cap.
    for (var i = 0; i < gates.length; i++) {
      await Future<void>.delayed(Duration.zero);
      expect(inFlight, lessThanOrEqualTo(2));
      gates[i].complete();
    }
    await done;

    expect(peak, 2);
    expect(collected, hasLength(8));
    expect(collected.toSet(), {for (var i = 0; i < 8; i++) i * 10});
  });

  test('mapBounded rejects a non-positive concurrency', () {
    expect(
      () => mapBounded<int, int>([1, 2], 0, (i) async => i),
      throwsArgumentError,
    );
  });
}
