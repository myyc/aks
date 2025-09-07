#ifndef VULKAN_PROCESSOR_H
#define VULKAN_PROCESSOR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize Vulkan
int vk_init();

// Check if Vulkan is available
int vk_is_available();

// Process image with Vulkan (basic version)
int vk_process_image(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    uint8_t** output_pixels
);

// Process image with Vulkan including tone curves
int vk_process_image_with_curves(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    const uint8_t* rgb_lut,    // 256 bytes tone curve LUT for RGB
    const uint8_t* red_lut,    // 256 bytes tone curve LUT for red
    const uint8_t* green_lut,  // 256 bytes tone curve LUT for green
    const uint8_t* blue_lut,   // 256 bytes tone curve LUT for blue
    uint8_t** output_pixels
);

// Process image with Vulkan including tone curves and cropping
int vk_process_image_with_curves_and_crop(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    float crop_left,    // Normalized 0-1
    float crop_top,     // Normalized 0-1
    float crop_right,   // Normalized 0-1
    float crop_bottom,  // Normalized 0-1
    const uint8_t* rgb_lut,    // 256 bytes tone curve LUT for RGB
    const uint8_t* red_lut,    // 256 bytes tone curve LUT for red
    const uint8_t* green_lut,  // 256 bytes tone curve LUT for green
    const uint8_t* blue_lut,   // 256 bytes tone curve LUT for blue
    uint8_t** output_pixels,
    int* output_width,   // Output cropped width
    int* output_height   // Output cropped height
);

// Free allocated buffer
void vk_free_buffer(uint8_t* buffer);

// Cleanup Vulkan
void vk_cleanup();

#ifdef __cplusplus
}
#endif

#endif // VULKAN_PROCESSOR_H