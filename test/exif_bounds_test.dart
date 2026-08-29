// The bounds checks in the EXIF parser, tested at the boundary.
//
// These came out of a mutation audit: thirteen deliberate faults injected into
// lib/, thirteen test runs, six of them still green. Five of the six were in
// exif.dart, and every one was an off-by-one in a bounds check -- the loop
// bound, the segment-end check, the tag-prefix check.
//
// That matters more here than it would elsewhere. This parser reads bytes out
// of a photograph somebody uploaded, so an off-by-one is not a cosmetic bug;
// it is a read past the end of an attacker-shaped buffer. The existing tests
// covered orientations that work, which is the comfortable input.
//
// Each test below names the mutation it kills, so a future reader can see why
// the fixture is shaped the way it is rather than tidying the awkwardness away.
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';
import 'package:test/test.dart';

/// Builds a JPEG that is nothing but SOI and one EXIF segment.
///
/// [trailing] bytes are appended after the segment. With none, the segment's
/// computed end lands exactly on the buffer length, which is the boundary the
/// `end > bytes.length` check sits on.
Uint8List jpegWithOrientation(
  int orientation, {
  Endian endian = Endian.little,
  List<int> trailing = const [],
  int entryCount = 1,
}) {
  final tiff = BytesBuilder();
  final marker = endian == Endian.little ? 0x49 : 0x4D;
  tiff.add([marker, marker]);

  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, endian);
    tiff.add(b.buffer.asUint8List());
  }

  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, endian);
    tiff.add(b.buffer.asUint8List());
  }

  u16(42);
  u32(8); // The IFD follows the header immediately.
  u16(entryCount);
  u16(0x0112); // Orientation.
  u16(3); // SHORT.
  u32(1); // One value.
  u16(orientation); // Stored inline...
  u16(0); // ...in the first half of a four-byte field.
  u32(0); // Next-IFD pointer: none.

  final tiffBytes = tiff.toBytes();
  final body = <int>[...'Exif\x00\x00'.codeUnits, ...tiffBytes];
  // The length field counts itself, so body + 2.
  final segmentLength = body.length + 2;

  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, // APP1
    (segmentLength >> 8) & 0xFF, segmentLength & 0xFF,
    ...body,
    ...trailing,
  ]);
}

void main() {
  group('exif bounds', () {
    test('reads a big-endian TIFF, not just a little-endian one', () {
      // Kills: exif.dart:111  `bytes[tiffStart] == 0x4D` -> `!=`.
      // Every existing fixture is little-endian ('II'), so inverting the
      // big-endian branch changed nothing and the suite stayed green. Canon
      // and Nikon write 'MM'.
      expect(exifOrientation(jpegWithOrientation(6, endian: Endian.big)), 6);
      expect(
        exifOrientation(jpegWithOrientation(6)),
        6,
        reason: 'little-endian must still work',
      );
    });

    test('accepts a segment that ends on the last byte of the file', () {
      // Kills: exif.dart:40  `end > bytes.length` -> `>=`.
      // A file with nothing after the EXIF segment is not malformed, and it
      // is what these fixtures are. The check has to be `>`, because `end ==
      // length` means the segment fits exactly.
      final exact = jpegWithOrientation(3);
      expect(exifOrientation(exact), 3);

      // Same file with a byte added: the segment no longer ends at the edge,
      // so this passes either way. It is here to show the pair apart.
      expect(exifOrientation(jpegWithOrientation(3, trailing: [0x00])), 3);
    });

    test('does not read an entry past the count the IFD declares', () {
      // Kills: exif.dart:124  `i < entryCount` -> `<=`.
      // Declaring zero entries with a real-looking entry sitting right after
      // the count: reading one too many finds an orientation that the file
      // does not claim to have.
      final lying = jpegWithOrientation(8, entryCount: 0);
      expect(
        exifOrientation(lying),
        1,
        reason:
            'an IFD that declares no entries has no orientation, '
            'whatever the bytes after the count happen to look like',
      );
    });

    test('a truncated file is answered, not thrown at', () {
      // The parser's contract: a malformed tag is never a reason to fail a
      // decode. Every prefix of a valid file has to come back with 1.
      final full = jpegWithOrientation(6);
      for (var cut = 0; cut < full.length; cut++) {
        final truncated = Uint8List.sublistView(full, 0, cut);
        expect(
          exifOrientation(truncated),
          isA<int>(),
          reason: 'threw on a $cut-byte prefix',
        );
      }
    });

    // Two mutants from the same audit are still alive and are meant to be.
    //
    //   exif.dart:22  `offset + 4 <= bytes.length` -> `<`
    //   exif.dart:98  `offset + tag.length > bytes.length` -> `>=`
    //
    // Both only behave differently when the buffer ends exactly on the bound,
    // and in both cases there is no room left for anything the parser could
    // report: four remaining bytes cannot hold an EXIF segment, and an "Exif"
    // marker ending at EOF is followed by no TIFF. Correct and mutant return
    // 1 for every input that reaches them. They are equivalent mutants, and a
    // test written to kill one would assert something that is not true.
    // Recorded here so the next audit does not spend an afternoon on it.

    test('every orientation outside 1..8 is treated as no rotation', () {
      // The doc promises this range. 0 and 9 are the values either side.
      for (final bad in [0, 9, 255]) {
        expect(exifOrientation(jpegWithOrientation(bad)), 1, reason: '$bad');
      }
      for (var good = 1; good <= 8; good++) {
        expect(exifOrientation(jpegWithOrientation(good)), good);
      }
    });
  });

  group('thumbnail bounds', () {
    // This one does NOT kill its mutant, and saying so is the point.
    //
    // The audit's sixth survivor was image_ffi_base.dart:411,
    // `longerSide <= maxDimension` -> `<`, which sends an image sitting
    // exactly on the limit through the resampler instead of returning it. I
    // wrote this expecting the round trip to show, and measured that it does
    // not: a 1:1 resample is byte-identical, so the mutant changes what the
    // code *costs*, never what it returns.
    //
    // The test stays because the behaviour is worth pinning -- at the limit
    // and under it must agree -- but it is not a guard against that mutation,
    // and a comment claiming otherwise would be the kind of decoration this
    // file was written to remove.
    test('an image exactly at the limit is not resampled', () {
      const size = 64;
      final pixels = Uint8List(size * size * 3);
      for (var i = 0; i < pixels.length; i++) {
        // A pattern a resampler would smear; a flat fill would survive one.
        pixels[i] = (i * 37) % 256;
      }
      final png = encodePng(pixels, width: size, height: size, channels: 3);

      final exact = thumbnailPng(png, maxDimension: size);
      final under = thumbnailPng(png, maxDimension: size + 1);

      expect(
        exact,
        equals(under),
        reason: 'at the limit and under it must both skip the resize',
      );
    });
  });
}
