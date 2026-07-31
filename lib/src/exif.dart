import 'dart:typed_data';

import 'image_ffi_base.dart';

/// Reads the EXIF orientation tag out of a JPEG.
///
/// Phone cameras write the sensor's pixels unrotated and record how the phone
/// was held in this tag, so a portrait photo decodes to a landscape buffer
/// that every viewer turns upright on the reader's behalf. Code that decodes
/// pixels directly — this package included, since stb does not parse EXIF —
/// sees the sideways version and produces a sideways thumbnail without any
/// error to suggest something went wrong.
///
/// Returns a value from 1 to 8 as EXIF defines them, and 1 (upright, no
/// transform) when the file is not a JPEG, carries no EXIF, or holds a value
/// outside that range. A malformed tag is never a reason to fail a decode.
int exifOrientation(Uint8List bytes) {
  // JPEG only: PNG has no orientation and stb's other formats predate it.
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;

  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) return 1; // Not on a marker; give up quietly.
    final marker = bytes[offset + 1];
    // Standalone markers carry no length.
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }
    // Start of scan: the entropy-coded data follows and EXIF cannot be after.
    if (marker == 0xDA || marker == 0xD9) return 1;

    if (offset + 4 > bytes.length) return 1;
    final segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segmentLength < 2) return 1;
    final body = offset + 4;
    final end = body + segmentLength - 2;
    if (end > bytes.length) return 1;

    if (marker == 0xE1 && _startsWith(bytes, body, 'Exif\x00\x00')) {
      final found = _orientationInTiff(bytes, body + 6, end);
      if (found != null) return found;
      return 1;
    }
    offset = end;
  }
  return 1;
}

/// Applies [orientation] to [image], returning the upright version.
///
/// Orientation 1 returns [image] unchanged. The other seven values are the
/// rotations and mirrorings EXIF defines; anything outside 1 to 8 is treated
/// as 1 rather than throwing, matching [exifOrientation].
DecodedImage applyExifOrientation(DecodedImage image, int orientation) {
  if (orientation <= 1 || orientation > 8) return image;

  final width = image.width;
  final height = image.height;
  final channels = image.channels;
  final source = image.pixels;
  // 5 to 8 swap the axes, so the result is as tall as the source is wide.
  final swapsAxes = orientation >= 5;
  final outWidth = swapsAxes ? height : width;
  final outHeight = swapsAxes ? width : height;
  final out = Uint8List(outWidth * outHeight * channels);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (dx, dy) = switch (orientation) {
        2 => (width - 1 - x, y), // mirrored
        3 => (width - 1 - x, height - 1 - y), // 180
        4 => (x, height - 1 - y), // mirrored, 180
        5 => (y, x), // mirrored, 90 CW
        6 => (height - 1 - y, x), // 90 CW
        7 => (height - 1 - y, width - 1 - x), // mirrored, 90 CCW
        _ => (y, width - 1 - x), // 8: 90 CCW
      };
      final from = (y * width + x) * channels;
      final to = (dy * outWidth + dx) * channels;
      for (var c = 0; c < channels; c++) {
        out[to + c] = source[from + c];
      }
    }
  }

  return DecodedImage(
    width: outWidth,
    height: outHeight,
    channels: channels,
    pixels: out,
  );
}

bool _startsWith(Uint8List bytes, int offset, String tag) {
  if (offset + tag.length > bytes.length) return false;
  for (var i = 0; i < tag.length; i++) {
    if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
  }
  return true;
}

/// Walks the TIFF header an EXIF segment wraps, looking for tag 0x0112.
int? _orientationInTiff(Uint8List bytes, int tiffStart, int limit) {
  if (tiffStart + 8 > limit) return null;
  final Endian endian;
  if (bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49) {
    endian = Endian.little; // 'II'
  } else if (bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D) {
    endian = Endian.big; // 'MM'
  } else {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint16(tiffStart + 2, endian) != 42) return null;

  final ifdOffset = data.getUint32(tiffStart + 4, endian);
  final ifd = tiffStart + ifdOffset;
  if (ifd + 2 > limit) return null;
  final entryCount = data.getUint16(ifd, endian);

  for (var i = 0; i < entryCount; i++) {
    final entry = ifd + 2 + i * 12;
    if (entry + 12 > limit) return null;
    if (data.getUint16(entry, endian) != 0x0112) continue;
    // Orientation is a SHORT, stored inline in the value field.
    final value = data.getUint16(entry + 8, endian);
    return value >= 1 && value <= 8 ? value : null;
  }
  return null;
}
