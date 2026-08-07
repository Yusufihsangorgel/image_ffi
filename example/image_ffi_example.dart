// Reads an image, prints its dimensions, and writes a 256px JPEG thumbnail
// next to it.
//
//   dart run example/image_ffi_example.dart path/to/photo.jpg
//
// With no argument it encodes a gradient and thumbnails that instead, so the
// example demonstrates the package without you having to find a file first.
import 'dart:io';
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';

/// A 1200x800 RGB gradient, encoded as a JPEG by the package itself.
///
/// Real photographic bytes would do as well; what matters for the thumbnail
/// path is that the source is large enough to actually be downscaled.
Uint8List _gradientJpeg() {
  const width = 1200;
  const height = 800;
  final pixels = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      pixels[i] = x * 255 ~/ (width - 1);
      pixels[i + 1] = y * 255 ~/ (height - 1);
      pixels[i + 2] = 128;
    }
  }
  return encodeJpeg(pixels, width: width, height: height, channels: 3);
}

void main(List<String> args) {
  final String label;
  final Uint8List bytes;
  if (args.isEmpty) {
    label = 'a generated gradient';
    bytes = _gradientJpeg();
    stdout.writeln('No image given, so this encodes one to work on.');
    stdout.writeln(
      'Pass a path to use your own: '
      'dart run example/image_ffi_example.dart photo.jpg\n',
    );
  } else {
    label = args.first;
    bytes = File(args.first).readAsBytesSync();
  }

  // Read the size without decoding the pixels.
  final info = imageInfo(bytes);
  stdout.writeln(
    '$label: ${info.width}x${info.height}, ${info.channels}ch, '
    '${bytes.length} bytes',
  );

  // Decode, downscale so the longer side is at most 256px, and JPEG-encode,
  // all in one native call.
  final thumbnail = thumbnailJpeg(bytes, maxDimension: 256, quality: 85);
  final thumbInfo = imageInfo(thumbnail);

  final output = args.isEmpty
      ? 'gradient.thumb.jpg'
      : '${args.first}.thumb.jpg';
  File(output).writeAsBytesSync(thumbnail);
  stdout.writeln(
    'wrote $output: ${thumbInfo.width}x${thumbInfo.height}, '
    '${thumbnail.length} bytes '
    '(${(100 * thumbnail.length / bytes.length).toStringAsFixed(1)}% of the '
    'original)',
  );
}
