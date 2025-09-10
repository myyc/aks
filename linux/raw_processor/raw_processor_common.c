#include "raw_processor_common.h"
#include <libraw/libraw.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Platform-specific includes
#if PLATFORM_MACOS
    #include <errno.h>
#endif

static char last_error[256] = {0};

// Platform-specific file checking
#if PLATFORM_MACOS
static int check_file_exists(const char* filename) {
    FILE* test = fopen(filename, "rb");
    if (!test) {
        snprintf(last_error, sizeof(last_error), "Cannot open file: %s (errno: %d - %s)", 
                filename, errno, strerror(errno));
        return 0;
    }
    fclose(test);
    return 1;
}
#else
static int check_file_exists(const char* filename) {
    // On other platforms, rely on libraw's error handling
    (void)filename; // Suppress unused parameter warning
    return 1;
}
#endif

void* raw_processor_init() {
    libraw_data_t* processor = libraw_init(0);
    if (!processor) {
        snprintf(last_error, sizeof(last_error), "Failed to initialize LibRaw");
        return NULL;
    }
    
    // Set default processing parameters
    processor->params.output_bps = 8;  // 8 bits per channel
    processor->params.output_color = 1; // sRGB
    processor->params.use_camera_wb = 1; // Use camera white balance
    processor->params.use_auto_wb = 0;
    processor->params.no_auto_bright = 1; // Disable auto-brightening to preserve RAW data
    processor->params.output_tiff = 0;
    
    return processor;
}

int raw_processor_open(void* processor, const char* filename) {
    if (!processor || !filename) {
        snprintf(last_error, sizeof(last_error), "Invalid processor or filename");
        return -1;
    }
    
    // Platform-specific file checking
    if (!check_file_exists(filename)) {
        return -1;
    }
    
    libraw_data_t* lr = (libraw_data_t*)processor;
    int ret = libraw_open_file(lr, filename);
    
    if (ret != LIBRAW_SUCCESS) {
        snprintf(last_error, sizeof(last_error), "Failed to open file: %s", libraw_strerror(ret));
        return ret;
    }
    
    ret = libraw_unpack(lr);
    if (ret != LIBRAW_SUCCESS) {
        snprintf(last_error, sizeof(last_error), "Failed to unpack RAW: %s", libraw_strerror(ret));
        return ret;
    }
    
    return LIBRAW_SUCCESS;
}

int raw_processor_process(void* processor) {
    if (!processor) {
        snprintf(last_error, sizeof(last_error), "Invalid processor");
        return -1;
    }
    
    libraw_data_t* lr = (libraw_data_t*)processor;
    int ret = libraw_dcraw_process(lr);
    
    if (ret != LIBRAW_SUCCESS) {
        snprintf(last_error, sizeof(last_error), "Failed to process RAW: %s", libraw_strerror(ret));
        return ret;
    }
    
    return LIBRAW_SUCCESS;
}

RawImageData* raw_processor_get_rgb(void* processor) {
    if (!processor) {
        snprintf(last_error, sizeof(last_error), "Invalid processor");
        return NULL;
    }
    
    libraw_data_t* lr = (libraw_data_t*)processor;
    int error_code = 0;
    
    libraw_processed_image_t* processed = libraw_dcraw_make_mem_image(lr, &error_code);
    if (!processed || error_code != LIBRAW_SUCCESS) {
        snprintf(last_error, sizeof(last_error), "Failed to create RGB image: %s", 
                 error_code ? libraw_strerror(error_code) : "Unknown error");
        return NULL;
    }
    
    RawImageData* image = (RawImageData*)malloc(sizeof(RawImageData));
    if (!image) {
        libraw_dcraw_clear_mem(processed);
        snprintf(last_error, sizeof(last_error), "Memory allocation failed");
        return NULL;
    }
    
    // Calculate actual image data size (without header)
    int data_size = processed->data_size;
    
    // Allocate and copy RGB data
    image->data = (uint8_t*)malloc(data_size);
    if (!image->data) {
        free(image);
        libraw_dcraw_clear_mem(processed);
        snprintf(last_error, sizeof(last_error), "Memory allocation failed for image data");
        return NULL;
    }
    
    memcpy(image->data, processed->data, data_size);
    image->size = data_size;
    
    // Fill image info
    image->info.width = processed->width;
    image->info.height = processed->height;
    image->info.bits = processed->bits;
    image->info.colors = processed->colors;
    
    libraw_dcraw_clear_mem(processed);
    return image;
}

void raw_processor_free_image(RawImageData* image) {
    if (image) {
        if (image->data) {
            free(image->data);
        }
        free(image);
    }
}

void raw_processor_cleanup(void* processor) {
    if (processor) {
        libraw_close((libraw_data_t*)processor);
    }
}

const char* raw_processor_get_error() {
    return last_error;
}