#ifndef RAW_PROCESSOR_COMMON_H
#define RAW_PROCESSOR_COMMON_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Image information structure
typedef struct {
    uint32_t width;
    uint32_t height;
    uint16_t bits;
    uint16_t colors;
} RawImageInfo;

// Image data structure
typedef struct {
    RawImageInfo info;
    uint8_t* data;
    size_t size;
} RawImageData;

// Platform detection
#if defined(_WIN32) || defined(_WIN64)
    #define PLATFORM_WINDOWS 1
#elif defined(__APPLE__)
    #define PLATFORM_MACOS 1
#elif defined(__linux__)
    #define PLATFORM_LINUX 1
#else
    #define PLATFORM_UNKNOWN 1
#endif

// Function declarations
void* raw_processor_init();
int raw_processor_open(void* processor, const char* filename);
int raw_processor_process(void* processor);
RawImageData* raw_processor_get_rgb(void* processor);
void raw_processor_free_image(RawImageData* image);
void raw_processor_cleanup(void* processor);
const char* raw_processor_get_error();

#ifdef __cplusplus
}
#endif

#endif // RAW_PROCESSOR_COMMON_H