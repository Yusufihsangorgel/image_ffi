/// Measures the frames a thumbnail costs you, and the frames it does not.
///
/// Decoding and downscaling a photo is fast, but it is not free, and on the
/// main isolate it is a stretch of time in which nothing else runs. In a
/// Flutter app that stretch is dropped frames. The async variants hand the work
/// to another isolate, and this counts the difference rather than asserting it.
///
/// The clock here is a timer firing every 16 ms, which is one frame at 60 Hz.
/// A tick that arrives late is a frame that would have been dropped.
///
///     dart run example/no_jank.dart
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';

/// A photo-sized JPEG, built here so the demo needs no file of its own.
Uint8List _photo({int width = 4000, int height = 3000}) {
  final pixels = Uint8List(width * height * 3);
  // A gradient with some noise: smooth enough to be a plausible photo, varied
  // enough that the JPEG does not compress down to nothing.
  for (var y = 0; y < height; y++) {
    final row = y * width * 3;
    for (var x = 0; x < width; x++) {
      final i = row + x * 3;
      pixels[i] = (x * 255 ~/ width);
      pixels[i + 1] = (y * 255 ~/ height);
      pixels[i + 2] = ((x ^ y) & 0xFF);
    }
  }
  return encodeJpeg(pixels, width: width, height: height, quality: 90);
}

/// Runs [work] while a 16 ms timer ticks, and reports the longest gap between
/// two ticks: the stretch in which the isolate answered nothing.
Future<({int worst, int elapsed})> _underAFrameClock(
  Future<void> Function() work,
) async {
  const frame = Duration(milliseconds: 16);
  var worst = 0;
  final since = Stopwatch()..start();
  final timer = Timer.periodic(frame, (_) {
    final gap = since.elapsedMilliseconds;
    since.reset();
    if (gap > worst) worst = gap;
  });

  final total = Stopwatch()..start();
  await work();
  total.stop();
  // The tick a blocking run held up is delivered only once the event loop runs
  // again. Cancelling the timer here, before yielding, would throw away the
  // very evidence being collected.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  timer.cancel();
  return (worst: worst, elapsed: total.elapsedMilliseconds);
}

Future<void> main() async {
  print('building a 4000x3000 JPEG to work on');
  final photo = _photo();
  print('${photo.length ~/ 1024} KB\n');

  // Let the isolate settle so the first measurement is not paying for startup.
  await Future<void>.delayed(const Duration(milliseconds: 200));

  final blocking = await _underAFrameClock(() async {
    for (var i = 0; i < 8; i++) {
      thumbnailJpeg(photo, maxDimension: 256);
    }
  });

  final offloaded = await _underAFrameClock(() async {
    for (var i = 0; i < 8; i++) {
      await thumbnailJpegAsync(photo, maxDimension: 256);
    }
  });

  // A whole folder at once. Awaiting eight `thumbnailJpegAsync` calls with
  // `Future.wait` would spawn eight isolates together, each holding a full
  // decoded buffer; over a real directory that is how you run out of memory.
  // `thumbnailJpegBatch` runs the same work but caps how many isolates are
  // live at once, here to two, and hands back each thumbnail as it lands.
  final folder = List.filled(8, photo);
  final batched = await _underAFrameClock(() async {
    await for (final _ in thumbnailJpegBatch(
      folder,
      maxDimension: 256,
      concurrency: 2,
    )) {
      // Write or collect the thumbnail here.
    }
  });

  void report(String label, ({int worst, int elapsed}) run) {
    print(label);
    final frames = run.worst ~/ 16;
    print(
      '  ${run.elapsed} ms of work, longest silence ${run.worst} ms, '
      'about $frames frame${frames == 1 ? '' : 's'}',
    );
  }

  report('8 thumbnails, on the main isolate', blocking);
  report('8 thumbnails, with thumbnailJpegAsync', offloaded);
  report('8 thumbnails, with thumbnailJpegBatch (concurrency 2)', batched);

  print(
    '\nThe offloaded runs are not faster, and are not meant to be: the '
    'work is the\nsame work. What changes is where it happens. Off the main '
    'isolate the frame\nclock keeps its cadence, which in an app is the '
    'difference between a list that\nscrolls and one that stutters. '
    '`thumbnailJpegBatch` adds the missing piece for\na folder: it stays off '
    'the main isolate and it bounds how many isolates run at\nonce, so a '
    'directory of photos does not spawn one full decode per file together.',
  );
}
