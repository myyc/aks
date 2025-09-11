#include "raw_processor_common.h"
#include <libraw/libraw.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <stddef.h>

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
    printf("DEBUG: C - raw_processor_get_rgb called\n");
    fflush(stdout);
    
    if (!processor) {
        snprintf(last_error, sizeof(last_error), "Invalid processor");
        return NULL;
    }
    
    libraw_data_t* lr = (libraw_data_t*)processor;
    int error_code = 0;
    
    printf("DEBUG: C - calling libraw_dcraw_make_mem_image\n");
    fflush(stdout);
    
    libraw_processed_image_t* processed = libraw_dcraw_make_mem_image(lr, &error_code);
    if (!processed || error_code != LIBRAW_SUCCESS) {
        printf("DEBUG: C - failed to create RGB image, error_code=%d\n", error_code);
        fflush(stdout);
        snprintf(last_error, sizeof(last_error), "Failed to create RGB image: %s", 
                 error_code ? libraw_strerror(error_code) : "Unknown error");
        return NULL;
    }
    
    printf("DEBUG: C - RGB image created successfully\n");
    fflush(stdout);
    
    printf("DEBUG: C - allocating RawImageData structure\n");
    fflush(stdout);
    
    RawImageData* image = (RawImageData*)malloc(sizeof(RawImageData));
    if (!image) {
        printf("DEBUG: C - failed to allocate RawImageData\n");
        fflush(stdout);
        libraw_dcraw_clear_mem(processed);
        snprintf(last_error, sizeof(last_error), "Memory allocation failed");
        return NULL;
    }
    
    printf("DEBUG: C - RawImageData allocated successfully\n");
    fflush(stdout);
    
    // Calculate actual image data size (without header)
    int data_size = processed->data_size;
    
    printf("DEBUG: C - allocating image data buffer, size=%d\n", data_size);
    fflush(stdout);
    
    // Allocate and copy RGB data
    image->data = (uint8_t*)malloc(data_size);
    if (!image->data) {
        printf("DEBUG: C - failed to allocate image data buffer\n");
        fflush(stdout);
        free(image);
        libraw_dcraw_clear_mem(processed);
        snprintf(last_error, sizeof(last_error), "Memory allocation failed for image data");
        return NULL;
    }
    
    printf("DEBUG: C - image data buffer allocated successfully\n");
    fflush(stdout);
    
    memcpy(image->data, processed->data, data_size);
    image->size = data_size;
    
    // Fill image info
    printf("DEBUG: C - filling image info: width=%u, height=%u, bits=%u, colors=%u\n", 
           processed->width, processed->height, processed->bits, processed->colors);
    fflush(stdout);
    
    image->info.width = processed->width;
    image->info.height = processed->height;
    image->info.bits = processed->bits;
    image->info.colors = processed->colors;
    
    printf("DEBUG: C - image info filled, checking sizes:\n");
    printf("DEBUG: C - sizeof(RawImageInfo)=%zu\n", sizeof(RawImageInfo));
    printf("DEBUG: C - sizeof(RawImageData)=%zu\n", sizeof(RawImageData));
    printf("DEBUG: C - offset of data in RawImageData=%zu\n", offsetof(RawImageData, data));
    fflush(stdout);
    
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

// Extract EXIF metadata from the opened RAW file
ExifData* raw_processor_get_exif(void* processor) {
    if (!processor) {
        snprintf(last_error, sizeof(last_error), "Invalid processor");
        return NULL;
    }
    
    libraw_data_t* lr = (libraw_data_t*)processor;
    
    // Allocate EXIF structure
    ExifData* exif = (ExifData*)calloc(1, sizeof(ExifData));
    if (!exif) {
        snprintf(last_error, sizeof(last_error), "Memory allocation failed for EXIF");
        return NULL;
    }
    
    // Extract camera info
    if (lr->idata.make[0] != '\0') {
        exif->make = strdup(lr->idata.make);
    }
    if (lr->idata.model[0] != '\0') {
        exif->model = strdup(lr->idata.model);
    }
    if (lr->idata.software[0] != '\0') {
        exif->software = strdup(lr->idata.software);
    }
    
    // Extract lens info
    libraw_lensinfo_t* lensinfo = &lr->lens;
    // Check if lens fields exist before accessing
    if (sizeof(lensinfo->LensMake) > 0 && lensinfo->LensMake[0] != '\0') {
        exif->lens_make = strdup(lensinfo->LensMake);
    }
    if (sizeof(lensinfo->Lens) > 0 && lensinfo->Lens[0] != '\0') {
        exif->lens_model = strdup(lensinfo->Lens);
    }
    
    // Extract shooting info with safe defaults
    exif->iso_speed = 0;
    exif->aperture = 0.0;
    exif->shutter_speed = 0.0;
    exif->focal_length = 0.0;
    exif->focal_length_35mm = 0.0;
    
    // Safely extract values if they exist
    if (offsetof(libraw_imgother_t, iso_speed) < sizeof(libraw_imgother_t)) {
        exif->iso_speed = lr->other.iso_speed;
    }
    if (offsetof(libraw_imgother_t, aperture) < sizeof(libraw_imgother_t)) {
        exif->aperture = lr->other.aperture;
    }
    if (offsetof(libraw_imgother_t, shutter) < sizeof(libraw_imgother_t)) {
        exif->shutter_speed = lr->other.shutter;
    }
    if (offsetof(libraw_imgother_t, focal_len) < sizeof(libraw_imgother_t)) {
        exif->focal_length = lr->other.focal_len;
    }
    
    // Extract timestamp (convert to string)
    if (lr->other.timestamp > 0) {
        char* time_str = (char*)malloc(20);
        if (time_str) {
            time_t timestamp = lr->other.timestamp;
            struct tm* timeinfo = localtime(&timestamp);
            if (timeinfo) {
                strftime(time_str, 20, "%Y:%m:%d %H:%M:%S", timeinfo);
                exif->datetime = time_str;
            } else {
                free(time_str);
            }
        }
    }
    
    // Extract exposure info (only fields available in libraw)
    exif->exposure_program = -1; // Not available in libraw_imgother_t
    exif->exposure_mode = -1; // Not available in libraw_imgother_t
    exif->metering_mode = -1; // Not available in libraw_imgother_t
    exif->exposure_compensation = 0.0; // Not available in libraw_imgother_t
    exif->flash_mode = -1; // Not available in libraw_imgother_t
    exif->white_balance = -1; // Not available in libraw_imgother_t
    
    return exif;
}

void raw_processor_free_exif(ExifData* exif) {
    if (exif) {
        if (exif->make) free(exif->make);
        if (exif->model) free(exif->model);
        if (exif->lens_make) free(exif->lens_make);
        if (exif->lens_model) free(exif->lens_model);
        if (exif->software) free(exif->software);
        if (exif->datetime) free((void*)exif->datetime);
        free(exif);
    }
}