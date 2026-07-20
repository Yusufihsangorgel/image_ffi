# Examples

## What a thumbnail costs the frame clock

```
dart run example/no_jank.dart
```

No image file needed: the demo builds a 4000x3000 JPEG, then makes eight
thumbnails twice, once on the main isolate and once with `thumbnailJpegAsync`.
While it works, a timer ticks every 16 ms, which is one frame at 60 Hz, and the
demo reports the longest gap between two ticks: the stretch in which the isolate
answered nothing at all.

```
8 thumbnails, on the main isolate
  413 ms of work, longest silence 413 ms, about 25 frames
8 thumbnails, with thumbnailJpegAsync
  409 ms of work, longest silence 18 ms, about 1 frame
```

The second run is not faster, and is not supposed to be. It is the same decode,
the same downscale, the same encode. What changes is where it happens. On the
main isolate those 413 ms are a hole in which nothing is painted and no gesture
is answered; in an app that is a list that stops scrolling while the thumbnails
land. Off the main isolate the clock keeps its cadence.

So: `thumbnailJpeg` in a script or a server handler, where blocking the isolate
is what you want. `thumbnailJpegAsync` anywhere a person is looking at the
screen. Both take the same arguments; the async ones copy the bytes to a worker
isolate and the result back, which is small next to the decode.

## The basics on a file of your own

```
dart run example/image_ffi_example.dart path/to/photo.jpg
```

Prints the dimensions without decoding the pixels, then writes a 256px JPEG
thumbnail next to the original. `imageInfo` reads only the header, which is the
cheap way to check a size or reject an upload before committing to a decode.

## Choosing among the calls

|                       | what it does                                    |
| --------------------- | ----------------------------------------------- |
| `imageInfo`           | width, height and channels from the header only |
| `thumbnailJpeg/Png`   | decode, downscale and encode in one native call |
| `decodeImage`         | pixels, when you need them yourself             |
| `resizePixels`        | downscale pixels you already hold               |
| `encodeJpeg/encodePng`| pixels back out to a file format                |

The thumbnail calls exist because the three-step version crosses the FFI
boundary three times and holds the full-size pixel buffer in Dart in between.
Reach for the pieces when you need something in the middle, and for
`thumbnail...` when you do not.

Use PNG when the source has transparency worth keeping, since a JPEG thumbnail
drops the alpha channel.
