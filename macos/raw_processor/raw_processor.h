#ifndef RAW_PROCESSOR_H
#define RAW_PROCESSOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int width;
    int height;
    int bits;
    int colors;
} RawImageInfo;

typedef struct {
    uint8_t* data;
    int size;
    RawImageInfo info;
} RawImageData;

// EXIF metadata structures
typedef struct {
    char* make;
    char* model;
    char* lens_make;
    char* lens_model;
    char* software;
    int iso_speed;
    double aperture;
    double shutter_speed;
    double focal_length;
    double focal_length_35mm;
    const char* datetime;
    int exposure_program;
    int exposure_mode;
    int metering_mode;
    double exposure_compensation;
    int flash_mode;
    int white_balance;
} ExifData;

// Initialize LibRaw processor
void* raw_processor_init();

// Open and unpack RAW file
int raw_processor_open(void* processor, const char* filename);

// Process the RAW image
int raw_processor_process(void* processor);

// Get RGB image data
RawImageData* raw_processor_get_rgb(void* processor);

// Extract EXIF metadata
ExifData* raw_processor_get_exif(void* processor);

// Free image data
void raw_processor_free_image(RawImageData* image);

// Free EXIF data
void raw_processor_free_exif(ExifData* exif);

// Cleanup processor
void raw_processor_cleanup(void* processor);

// Get last error message
const char* raw_processor_get_error();

#ifdef __cplusplus
}
#endif

#endif // RAW_PROCESSOR_H