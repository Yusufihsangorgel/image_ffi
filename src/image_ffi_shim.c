// C ABI shim over Sean Barrett's stb single-file image libraries.
//
// The three stb implementations are compiled exactly once here: this is the
// only translation unit that defines STB_IMAGE_IMPLEMENTATION and friends.
// Everything exported to Dart is a thin `extern "C"` wrapper that takes plain
// pointers and lengths, returns a heap buffer the caller copies out and then
// frees, and reports failure through a null return plus stbi_failure_reason().
//
// stb allocates decode output with STBI_MALLOC (plain malloc here, since it is
// not overridden) and resize/encode output buffers are allocated with malloc
// in this file, so every buffer handed to Dart is freed with the standard
// free(): imgffi_free_image() for decode output and imgffi_free_buffer() for
// resize and encode output. Keeping the pairing explicit documents the intent
// even though both currently resolve to free().

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image.h"
#include "stb_image_write.h"
#include "stb_image_resize2.h"

#include <stdlib.h>
#include <string.h>

// MSVC exports nothing from a DLL by default, and CBuilder compiles the
// non-Windows targets with hidden visibility, so mark the C ABI entry points
// exported explicitly. stb's own symbols stay internal to the library.
#if defined(_WIN32)
#define IMGFFI_EXPORT __declspec(dllexport)
#else
#define IMGFFI_EXPORT __attribute__((visibility("default")))
#endif

// Decodes an encoded image (PNG/JPEG/BMP/GIF/PSD/TGA/HDR/PIC) from memory.
//
// On success returns a freshly allocated pixel buffer of
// out_w * out_h * out_channels bytes (row-major, 8 bits per channel) and
// writes the dimensions and channel count through the out pointers. When
// force_channels is non-zero (1..4) the buffer has that many channels;
// otherwise it has the file's native channel count. Returns NULL on failure,
// in which case imgffi_failure_reason() explains why. Free the result with
// imgffi_free_image().
IMGFFI_EXPORT unsigned char* imgffi_decode(const unsigned char* data, int len,
                                           int force_channels, int* out_w,
                                           int* out_h, int* out_channels) {
  int width = 0;
  int height = 0;
  int native_channels = 0;
  unsigned char* pixels = stbi_load_from_memory(
      data, len, &width, &height, &native_channels, force_channels);
  if (pixels == NULL) {
    return NULL;
  }
  *out_w = width;
  *out_h = height;
  *out_channels = force_channels != 0 ? force_channels : native_channels;
  return pixels;
}

// Frees a buffer returned by imgffi_decode().
IMGFFI_EXPORT void imgffi_free_image(unsigned char* pixels) {
  stbi_image_free(pixels);
}

// Reads width, height and channel count without decoding the pixels. Returns 1
// on success and 0 if the header could not be parsed.
IMGFFI_EXPORT int imgffi_info(const unsigned char* data, int len, int* out_w,
                              int* out_h, int* out_channels) {
  return stbi_info_from_memory(data, len, out_w, out_h, out_channels);
}

// High-quality sRGB-correct resize. channels is the pixel layout (1..4); a
// value of 4 is treated as non-premultiplied RGBA so alpha is handled
// correctly. Returns a freshly allocated dst_w * dst_h * channels buffer, or
// Maps a plain channel count to the stb pixel layout that handles alpha
// correctly. A raw `(stbir_pixel_layout)channels` cast is wrong for 2-channel
// input: value 2 is STBIR_2CHANNEL (two colour channels, no alpha), but a
// 2-channel image is grayscale + alpha, so it must be STBIR_RA for edges
// against transparency to stay clean. 1/3/4 already line up (1CHANNEL / RGB /
// RGBA), but map them explicitly so the intent is on the page.
static stbir_pixel_layout imgffi_layout(int channels) {
  switch (channels) {
    case 1:
      return STBIR_1CHANNEL;
    case 2:
      return STBIR_RA;  // gray + alpha, not two colour channels
    case 3:
      return STBIR_RGB;
    default:
      return STBIR_RGBA;  // non-premultiplied alpha
  }
}

// NULL on failure. Free the result with imgffi_free_buffer(). `linear` selects
// the colour space the resample runs in: 0 treats the colour channels as sRGB
// (the right default for photographic/UI images), 1 treats them as linear
// (for masks, data, or already-linear pixels, where an sRGB curve would
// distort the values). Alpha is always resampled linearly in both.
IMGFFI_EXPORT unsigned char* imgffi_resize(const unsigned char* input,
                                           int src_w, int src_h, int dst_w,
                                           int dst_h, int channels, int linear) {
  const size_t output_size =
      (size_t)dst_w * (size_t)dst_h * (size_t)channels;
  unsigned char* output = (unsigned char*)malloc(output_size);
  if (output == NULL) {
    return NULL;
  }
  const stbir_pixel_layout layout = imgffi_layout(channels);
  unsigned char* result =
      linear ? stbir_resize_uint8_linear(input, src_w, src_h, 0, output, dst_w,
                                         dst_h, 0, layout)
             : stbir_resize_uint8_srgb(input, src_w, src_h, 0, output, dst_w,
                                       dst_h, 0, layout);
  if (result == NULL) {
    free(output);
    return NULL;
  }
  return output;
}

// A growable byte buffer used to collect encoder output. stb's write callback
// is invoked one or more times with chunks of the encoded stream; the buffer
// doubles its capacity as needed and records an allocation failure so the
// caller can detect it.
typedef struct {
  unsigned char* data;
  size_t size;
  size_t capacity;
  int failed;
} imgffi_buffer;

static void imgffi_write_cb(void* context, void* data, int size) {
  imgffi_buffer* buffer = (imgffi_buffer*)context;
  if (buffer->failed || size <= 0) {
    return;
  }
  const size_t chunk = (size_t)size;
  if (buffer->size + chunk > buffer->capacity) {
    size_t new_capacity = buffer->capacity == 0 ? 4096 : buffer->capacity;
    while (new_capacity < buffer->size + chunk) {
      new_capacity *= 2;
    }
    unsigned char* grown =
        (unsigned char*)realloc(buffer->data, new_capacity);
    if (grown == NULL) {
      buffer->failed = 1;
      return;
    }
    buffer->data = grown;
    buffer->capacity = new_capacity;
  }
  memcpy(buffer->data + buffer->size, data, chunk);
  buffer->size += chunk;
}

// Encodes pixels as a PNG into memory. Returns a freshly allocated buffer of
// *out_len bytes, or NULL on failure. Free the result with
// imgffi_free_buffer().
IMGFFI_EXPORT unsigned char* imgffi_encode_png(const unsigned char* pixels,
                                               int w, int h, int channels,
                                               int* out_len) {
  imgffi_buffer buffer = {NULL, 0, 0, 0};
  const int ok = stbi_write_png_to_func(imgffi_write_cb, &buffer, w, h,
                                         channels, pixels, 0);
  if (!ok || buffer.failed) {
    free(buffer.data);
    return NULL;
  }
  *out_len = (int)buffer.size;
  return buffer.data;
}

// Encodes pixels as a JPEG into memory at the given quality (1..100). For
// four-channel input the alpha channel is ignored, matching stb. Returns a
// freshly allocated buffer of *out_len bytes, or NULL on failure. Free the
// result with imgffi_free_buffer().
IMGFFI_EXPORT unsigned char* imgffi_encode_jpg(const unsigned char* pixels,
                                               int w, int h, int channels,
                                               int quality, int* out_len) {
  imgffi_buffer buffer = {NULL, 0, 0, 0};
  const int ok = stbi_write_jpg_to_func(imgffi_write_cb, &buffer, w, h,
                                         channels, pixels, quality);
  if (!ok || buffer.failed) {
    free(buffer.data);
    return NULL;
  }
  *out_len = (int)buffer.size;
  return buffer.data;
}

// Frees a buffer returned by imgffi_resize(), imgffi_encode_png() or
// imgffi_encode_jpg().
IMGFFI_EXPORT void imgffi_free_buffer(unsigned char* buffer) { free(buffer); }

// Returns stb's most recent failure reason as a NUL-terminated C string, or
// NULL if none is available. The string is owned by stb and must not be freed.
IMGFFI_EXPORT const char* imgffi_failure_reason(void) {
  return stbi_failure_reason();
}
