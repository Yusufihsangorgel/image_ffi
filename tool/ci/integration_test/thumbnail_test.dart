// Runs inside the app the compat workflow generates, not in this package:
// flutter_test and integration_test resolve there. tool/ci/prepare_app.dart
// copies it and its fixture to the app.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_ffi/image_ffi.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('decodes a bundled PNG and makes a JPEG thumbnail', () async {
    // 96x64 RGB. The pixel at (x, y) is (2x, 3y, 128).
    final data = await rootBundle.load('assets/gradient_96x64.png');
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final image = decodeImage(png);
    expect(image.width, 96);
    expect(image.height, 64);
    expect(image.channels, 3);
    final at = (20 * 96 + 10) * 3;
    expect(image.pixels.sublist(at, at + 3), [20, 60, 128]);

    final thumb = thumbnailJpeg(png, maxDimension: 48);
    expect(thumb.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    final info = imageInfo(thumb);
    expect(info.width, 48);
    expect(info.height, 32);
  });

  test('rejects garbage with ImageFfiException', () {
    final garbage = Uint8List.fromList(List<int>.generate(64, (i) => i));

    expect(() => decodeImage(garbage), throwsA(isA<ImageFfiException>()));
  });
}
