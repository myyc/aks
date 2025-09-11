#include "raw_processor.h"
#include <libraw/libraw.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

static char last_error[256] = {0};

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
    if (lensinfo->LensMake[0] != '\0') {
        exif->lens_make = strdup(lensinfo->LensMake);
    }
    if (lensinfo->Lens[0] != '\0') {
        exif->lens_model = strdup(lensinfo->Lens);
    }
    
    // Extract shooting info
    exif->iso_speed = lr->other.iso_speed;
    exif->aperture = lr->other.aperture;
    exif->shutter_speed = lr->other.shutter;
    exif->focal_length = lr->other.focal_len;
    
    // Extract 35mm equivalent focal length if available
    if (lr->lens.FocalLengthIn35mmFormat > 0) {
        exif->focal_length_35mm = lr->lens.FocalLengthIn35mmFormat;
    }
    
    // Extract timestamp (convert to string)
    if (lr->other.timestamp > 0) {
        char time_str[20];
        struct tm* tm_info = localtime(&lr->other.timestamp);
        strftime(time_str, sizeof(time_str), "%Y:%m:%d %H:%M:%S", tm_info);
        exif->datetime = strdup(time_str);
    } else {
        exif->datetime = strdup("");
    }
    
    // Extract exposure info - using available fields
    exif->exposure_program = 0; // Not available in lr->other
    exif->exposure_mode = 0; // Not available in lr->other
    exif->metering_mode = 0; // Not available in lr->other
    exif->exposure_compensation = 0.0; // Not available in lr->other
    exif->flash_mode = 0; // Not available in lr->other
    exif->white_balance = lr->other.shot_order; // Using shot_order instead of shot_select
    
    return exif;
}

void raw_processor_free_exif(ExifData* exif) {
    if (exif) {
        if (exif->make) free(exif->make);
        if (exif->model) free(exif->model);
        if (exif->lens_make) free(exif->lens_make);
        if (exif->lens_model) free(exif->lens_model);
        if (exif->software) free(exif->software);
        free(exif);
    }
}