// Reads an image file, prints its dimensions, and writes a 256px JPEG
// thumbnail next to it. Run with:
//
//   dart run example/image_ffi_example.dart path/to/photo.jpg
import 'dart:io';

import 'package:image_ffi/image_ffi.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run example/image_ffi_example.dart <image>');
    exitCode = 64; // EX_USAGE
    return;
  }

  final path = args.first;
  final bytes = File(path).readAsBytesSync();

  // Read the size without decoding the pixels.
  final info = imageInfo(bytes);
  stdout.writeln('$path: ${info.width}x${info.height}, ${info.channels}ch');

  // Decode, downscale so the longer side is at most 256px, and JPEG-encode,
  // all in one native call.
  final thumbnail = thumbnailJpeg(bytes, maxDimension: 256, quality: 85);

  final output = '$path.thumb.jpg';
  File(output).writeAsBytesSync(thumbnail);
  stdout.writeln('wrote $output (${thumbnail.length} bytes)');
}
