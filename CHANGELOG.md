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
