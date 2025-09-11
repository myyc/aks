#ifndef RAW_PROCESSOR_H
#define RAW_PROCESSOR_H

// Include the common header to get the correct structure definitions
#ifdef LIBRARY_COMPILATION
  #include "raw_processor_common.h"
#else
  #include "../../lib/ffi/raw/raw_processor_common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ExifData is already defined in raw_processor_common.h

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