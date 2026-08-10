// Two greys, from the same checkerboard, resized two ways.
//
//   dart run tool/gamma_figure.dart
//
// The numbers come from `example/gamma_correct_resize.dart`, run here rather
// than copied, so the swatches are the bytes the library actually produced.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image_ffi/image_ffi.dart';

const bg = '#14161C';
const ink = '#d8dee9';
const dim = '#8b93a3';

Uint8List checkerboard(int size) {
  final pixels = Uint8List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      pixels[y * size + x] = (x + y).isEven ? 255 : 0;
    }
  }
  return pixels;
}

double toLight(int code) {
  final c = code / 255;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

int resizeTo1(Uint8List board, int size, ResizeColorSpace space) =>
    resizePixels(
      board,
      srcWidth: size,
      srcHeight: size,
      dstWidth: 1,
      dstHeight: 1,
      channels: 1,
      colorSpace: space,
    )[0];

String hex(int v) => v.toRadixString(16).padLeft(2, '0');

void main() {
  const size = 256;
  final board = checkerboard(size);
  final srgb = resizeTo1(board, size, ResizeColorSpace.srgb);
  final linear = resizeTo1(board, size, ResizeColorSpace.linear);

  // The code that emits half of white's light, which is what the board does.
  final target = toLight(255) * 0.5;
  var correct = 0;
  for (var c = 0; c <= 255; c++) {
    if (toLight(c) >= target) {
      correct = c;
      break;
    }
  }

  const w = 760.0, h = 300.0, sw = 200.0;
  final b = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${w.toInt()}" '
      'height="${h.toInt()}" viewBox="0 0 ${w.toInt()} ${h.toInt()}">',
    )
    ..writeln('  <rect width="100%" height="100%" fill="$bg"/>')
    ..writeln(
      '  <text x="40" y="36" fill="$ink" font-size="15" '
      'font-family="Menlo, monospace">the same checkerboard, shrunk to one '
      'pixel</text>',
    )
    ..writeln(
      '  <text x="40" y="56" fill="$dim" font-size="11.5" '
      'font-family="Menlo, monospace">half black, half white, so the honest '
      'answer is the grey that emits half the light: $correct</text>',
    );

  var x = 40.0;
  for (final (label, value) in [
    ('ResizeColorSpace.srgb', srgb),
    ('ResizeColorSpace.linear', linear),
  ]) {
    final off = value - correct;
    b
      ..writeln(
        '  <rect x="$x" y="88" width="$sw" height="130" '
        'fill="#${hex(value)}${hex(value)}${hex(value)}" rx="3"/>',
      )
      ..writeln(
        '  <text x="${x + sw / 2}" y="240" fill="$ink" font-size="12" '
        'font-family="Menlo, monospace" text-anchor="middle">$label</text>',
      )
      ..writeln(
        '  <text x="${x + sw / 2}" y="260" fill="$dim" font-size="11.5" '
        'font-family="Menlo, monospace" text-anchor="middle">'
        '$value${off == 0 ? ', the light-correct grey' : ', $off too dark'}'
        '</text>',
      );
    x += sw + 60;
  }

  b
    ..writeln(
      '  <text x="40" y="288" fill="$dim" font-size="11" '
      'font-family="Menlo, monospace">both are one call to resizePixels; '
      'the argument is the whole difference, and srgb is the default</text>',
    )
    ..writeln('</svg>');

  File('doc/gamma-resize.svg').writeAsStringSync(b.toString());
  stdout
    ..writeln('wrote doc/gamma-resize.svg')
    ..writeln('  srgb $srgb, linear $linear, light-correct $correct')
    ..writeln(
      'render: rsvg-convert -z 2 doc/gamma-resize.svg '
      '-o doc/gamma-resize.png',
    );
}
