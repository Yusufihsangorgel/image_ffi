## 0.3.0

- Add `thumbnailPng`, a one-call decode, resize, and PNG encode that keeps the
  alpha channel. Reach for it on logos, icons, screenshots, and anything with
  transparency, where `thumbnailJpeg` would flatten the transparent areas onto a
  background.

## 0.2.1

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.2.0

- `resizePixels` now takes a `colorSpace` (`ResizeColorSpace.srgb` by default,
  or `.linear`). sRGB is right for photographic and UI images; linear is for
  masks and data pixels where an sRGB curve would distort the values.
- Fix: 2-channel input is now resampled as grayscale + alpha (STBIR_RA) instead
  of two colour channels, so edges against transparency stay clean for gray+alpha
  images. Previously a 2-channel resize let transparent pixels bleed into the
  colour.

## 0.1.0

- Initial release.
- Decode PNG, JPEG, BMP, GIF, PSD, TGA, HDR and PIC from memory
  (`decodeImage`), with an optional forced channel count.
- Read dimensions and channel count without decoding pixels (`imageInfo`).
- High-quality, sRGB-correct resize (`resizePixels`).
- JPEG and PNG encoding to memory (`encodeJpeg`, `encodePng`).
- One-call thumbnail generation (`thumbnailJpeg`): decode, aspect-preserving
  downscale and JPEG encode.
- Native stb sources compiled from source by a Dart build hook; no prebuilt
  binaries.
