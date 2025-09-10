#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t* data;
    size_t size;
} JpegBuffer;

// FFI bindings for libjpeg-turbo
extern "C" {
    // Initialize JPEG compression
    void* jpeg_compress_init(int width, int height, int quality);
    
    // Compress RGB data to JPEG
    JpegBuffer jpeg_compress_rgb(void* handle, uint8_t* rgb_data);
    
    // Compress RGBA data to JPEG (ignores alpha)
    JpegBuffer jpeg_compress_rgba(void* handle, uint8_t* rgba_data);
    
    // Free JPEG buffer
    void jpeg_free_buffer(JpegBuffer buffer);
    
    // Cleanup compression handle
    void jpeg_compress_cleanup(void* handle);
}