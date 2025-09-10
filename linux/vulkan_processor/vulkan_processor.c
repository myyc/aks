#include "vulkan_processor.h"
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Verbose logging flag - set via environment variable VULKAN_VERBOSE=1
static int verbose_logging = 0;

#define VLOG(...) do { if (verbose_logging) printf(__VA_ARGS__); } while(0)

// Vulkan state
static VkInstance instance = VK_NULL_HANDLE;
static VkPhysicalDevice physical_device = VK_NULL_HANDLE;
static VkDevice device = VK_NULL_HANDLE;
static VkQueue compute_queue = VK_NULL_HANDLE;
static VkCommandPool command_pool = VK_NULL_HANDLE;
static VkDescriptorPool descriptor_pool = VK_NULL_HANDLE;
static VkPipeline compute_pipeline = VK_NULL_HANDLE;
static VkPipelineLayout pipeline_layout = VK_NULL_HANDLE;
static VkDescriptorSetLayout descriptor_set_layout = VK_NULL_HANDLE;
static uint32_t queue_family_index = 0;
static VkShaderModule compute_shader_module = VK_NULL_HANDLE;

// Buffer management
static VkBuffer staging_buffer = VK_NULL_HANDLE;
static VkDeviceMemory staging_memory = VK_NULL_HANDLE;
static VkCommandBuffer command_buffer = VK_NULL_HANDLE;

static int initialized = 0;
static int processing = 0; // Guard against concurrent processing

// Check for verbose logging on first call
static void check_verbose_logging() {
    static int checked = 0;
    if (!checked) {
        const char* env = getenv("VULKAN_VERBOSE");
        verbose_logging = (env && strcmp(env, "1") == 0);
        if (!verbose_logging) {
            // Also disable if explicitly set to 0 or not set
            verbose_logging = 0;
        }
        checked = 1;
        // Print once to stderr to indicate verbose mode status
        if (verbose_logging) {
            fprintf(stderr, "[Vulkan] Verbose logging enabled (VULKAN_VERBOSE=1)\n");
        }
    }
}

// Helper to find memory type
static uint32_t find_memory_type(uint32_t type_filter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties mem_properties;
    vkGetPhysicalDeviceMemoryProperties(physical_device, &mem_properties);
    
    for (uint32_t i = 0; i < mem_properties.memoryTypeCount; i++) {
        if ((type_filter & (1 << i)) && 
            (mem_properties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    
    return ~0u;
}

// Helper function to check Vulkan result
static int check_vk_result(VkResult result, const char* operation) {
    if (result != VK_SUCCESS) {
        fprintf(stderr, "Vulkan error in %s: %d\n", operation, result);
        return 0;
    }
    return 1;
}

int vk_init() {
    check_verbose_logging();
    if (initialized) return 1;
    
    // Create Vulkan instance
    VkApplicationInfo app_info = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "aks Image Processor",
        .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "No Engine",
        .engineVersion = VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = VK_API_VERSION_1_2
    };
    
    VkInstanceCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledLayerCount = 0,
        .enabledExtensionCount = 0
    };
    
    VkResult result = vkCreateInstance(&create_info, NULL, &instance);
    if (!check_vk_result(result, "vkCreateInstance")) {
        return 0;
    }
    
    // Get physical device
    uint32_t device_count = 0;
    vkEnumeratePhysicalDevices(instance, &device_count, NULL);
    if (device_count == 0) {
        fprintf(stderr, "No Vulkan devices found\n");
        return 0;
    }
    
    VkPhysicalDevice* devices = malloc(sizeof(VkPhysicalDevice) * device_count);
    vkEnumeratePhysicalDevices(instance, &device_count, devices);
    
    // Pick first device with compute support
    for (uint32_t i = 0; i < device_count; i++) {
        uint32_t queue_family_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_family_count, NULL);
        
        VkQueueFamilyProperties* queue_families = malloc(sizeof(VkQueueFamilyProperties) * queue_family_count);
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_family_count, queue_families);
        
        for (uint32_t j = 0; j < queue_family_count; j++) {
            if (queue_families[j].queueFlags & VK_QUEUE_COMPUTE_BIT) {
                physical_device = devices[i];
                queue_family_index = j;
                break;
            }
        }
        free(queue_families);
        
        if (physical_device != VK_NULL_HANDLE) break;
    }
    free(devices);
    
    if (physical_device == VK_NULL_HANDLE) {
        fprintf(stderr, "No suitable Vulkan device found\n");
        return 0;
    }
    
    // Create logical device
    float queue_priority = 1.0f;
    VkDeviceQueueCreateInfo queue_create_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = queue_family_index,
        .queueCount = 1,
        .pQueuePriorities = &queue_priority
    };
    
    VkPhysicalDeviceFeatures device_features = {};
    
    VkDeviceCreateInfo device_create_info = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_create_info,
        .pEnabledFeatures = &device_features,
        .enabledExtensionCount = 0,
        .enabledLayerCount = 0
    };
    
    result = vkCreateDevice(physical_device, &device_create_info, NULL, &device);
    if (!check_vk_result(result, "vkCreateDevice")) {
        return 0;
    }
    
    // Get compute queue
    vkGetDeviceQueue(device, queue_family_index, 0, &compute_queue);
    
    // Create command pool
    VkCommandPoolCreateInfo pool_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_index
    };
    
    result = vkCreateCommandPool(device, &pool_info, NULL, &command_pool);
    if (!check_vk_result(result, "vkCreateCommandPool")) {
        return 0;
    }
    
    // Create descriptor set layout
    VkDescriptorSetLayoutBinding bindings[] = {
        // Input image buffer
        {
            .binding = 0,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        },
        // Output image buffer
        {
            .binding = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        },
        // Uniform buffer for parameters
        {
            .binding = 2,
            .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        },
        // RGB tone curve LUT
        {
            .binding = 3,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        },
        // Red tone curve LUT
        {
            .binding = 4,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        },
        // Green tone curve LUT
        {
            .binding = 5,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        },
        // Blue tone curve LUT
        {
            .binding = 6,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .descriptorCount = 1,
            .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = NULL
        }
    };
    
    VkDescriptorSetLayoutCreateInfo layout_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 7,
        .pBindings = bindings
    };
    
    result = vkCreateDescriptorSetLayout(device, &layout_info, NULL, &descriptor_set_layout);
    if (!check_vk_result(result, "vkCreateDescriptorSetLayout")) {
        vk_cleanup();
        return 0;
    }
    
    // Create pipeline layout
    VkPipelineLayoutCreateInfo pipeline_layout_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &descriptor_set_layout,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = NULL
    };
    
    result = vkCreatePipelineLayout(device, &pipeline_layout_info, NULL, &pipeline_layout);
    if (!check_vk_result(result, "vkCreatePipelineLayout")) {
        vk_cleanup();
        return 0;
    }
    
    // Load compute shader - try different paths
    const char* shader_paths[] = {
        "linux/vulkan_processor/shaders/image_process.spv",
        "linux/build/shaders/image_process.spv",
        "shaders/image_process.spv",
        "../shaders/image_process.spv",
        "build/shaders/image_process.spv",
        "bundle/data/shaders/image_process.spv",
        "build/linux/x64/debug/shaders/image_process.spv",
        "build/linux/x64/debug/bundle/data/shaders/image_process.spv",
        "/var/home/o/Projects/aks/build/linux/x64/debug/shaders/image_process.spv",
        NULL
    };
    
    FILE* shader_file = NULL;
    for (int i = 0; shader_paths[i] != NULL; i++) {
        shader_file = fopen(shader_paths[i], "rb");
        if (shader_file) {
            VLOG("Found shader at: %s\n", shader_paths[i]);
            break;
        }
    }
    
    if (!shader_file) {
        fprintf(stderr, "Failed to find shader file\n");
        vk_cleanup();
        return 0;
    }
    
    fseek(shader_file, 0, SEEK_END);
    size_t shader_size = ftell(shader_file);
    fseek(shader_file, 0, SEEK_SET);
    
    uint32_t* shader_code = (uint32_t*)malloc(shader_size);
    fread(shader_code, 1, shader_size, shader_file);
    fclose(shader_file);
    
    VkShaderModuleCreateInfo shader_info = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = shader_size,
        .pCode = shader_code
    };
    
    result = vkCreateShaderModule(device, &shader_info, NULL, &compute_shader_module);
    free(shader_code);
    
    if (!check_vk_result(result, "vkCreateShaderModule")) {
        vk_cleanup();
        return 0;
    }
    
    // Create compute pipeline
    VkPipelineShaderStageCreateInfo shader_stage_info = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = VK_SHADER_STAGE_COMPUTE_BIT,
        .module = compute_shader_module,
        .pName = "main"
    };
    
    VkComputePipelineCreateInfo pipeline_info = {
        .sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = shader_stage_info,
        .layout = pipeline_layout,
        .basePipelineHandle = VK_NULL_HANDLE,
        .basePipelineIndex = -1
    };
    
    result = vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &compute_pipeline);
    if (!check_vk_result(result, "vkCreateComputePipelines")) {
        vk_cleanup();
        return 0;
    }
    
    // Create descriptor pool (allow multiple sets for reuse)
    VkDescriptorPoolSize pool_sizes[] = {
        { .type = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 30 },  // Increased for tone curve LUTs
        { .type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 10 }
    };
    
    VkDescriptorPoolCreateInfo desc_pool_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .maxSets = 10,
        .poolSizeCount = 2,
        .pPoolSizes = pool_sizes
    };
    
    result = vkCreateDescriptorPool(device, &desc_pool_info, NULL, &descriptor_pool);
    if (!check_vk_result(result, "vkCreateDescriptorPool")) {
        vk_cleanup();
        return 0;
    }
    
    // Allocate command buffer
    VkCommandBufferAllocateInfo cmd_alloc_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1
    };
    
    result = vkAllocateCommandBuffers(device, &cmd_alloc_info, &command_buffer);
    if (!check_vk_result(result, "vkAllocateCommandBuffers")) {
        vk_cleanup();
        return 0;
    }
    
    initialized = 1;
    VLOG("Vulkan initialized successfully\n");
    return 1;
}

int vk_is_available() {
    // Try to create instance to check availability
    VkApplicationInfo app_info = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .apiVersion = VK_API_VERSION_1_0
    };
    
    VkInstanceCreateInfo create_info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info
    };
    
    VkInstance test_instance;
    VkResult result = vkCreateInstance(&create_info, NULL, &test_instance);
    
    if (result == VK_SUCCESS) {
        vkDestroyInstance(test_instance, NULL);
        return 1;
    }
    
    return 0;
}

int vk_process_image(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    uint8_t** output_pixels
) {
    // Create identity LUTs for backward compatibility
    uint8_t identity_lut[256];
    for (int i = 0; i < 256; i++) {
        identity_lut[i] = i;
    }
    
    // Call the curves version with identity LUTs
    return vk_process_image_with_curves(
        input_pixels, width, height,
        adjustments, adjustment_count,
        identity_lut, identity_lut, identity_lut, identity_lut,
        output_pixels
    );
}

// Original implementation moved to internal function
static int vk_process_image_internal(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    const uint8_t* rgb_lut,
    const uint8_t* red_lut,
    const uint8_t* green_lut,
    const uint8_t* blue_lut,
    uint8_t** output_pixels
) {
    check_verbose_logging();
    
    if (!initialized) {
        fprintf(stderr, "Vulkan not initialized\n");
        return 0;
    }
    
    // Guard against concurrent processing
    if (processing) {
        VLOG("vk_process_image_internal: Already processing, skipping\n");
        return 0;
    }
    processing = 1;
    
    VLOG("vk_process_image_internal: Processing %dx%d image with %d adjustments\n", width, height, adjustment_count);
    
    VkResult result;
    
    // Calculate output dimensions based on crop parameters
    int output_width = width;
    int output_height = height;
    float crop_left = 0.0f, crop_top = 0.0f, crop_right = 1.0f, crop_bottom = 1.0f;
    
    if (adjustment_count >= 18) {
        // Extract crop parameters from indices 14-17
        crop_left = adjustments[14];
        crop_top = adjustments[15];
        crop_right = adjustments[16];
        crop_bottom = adjustments[17];
        
        // Calculate cropped dimensions
        // Match CPU's approach: round to pixels first, then subtract
        int crop_left_px = (int)round(crop_left * width);
        int crop_top_px = (int)round(crop_top * height);
        int crop_right_px = (int)round(crop_right * width);
        int crop_bottom_px = (int)round(crop_bottom * height);
        
        output_width = crop_right_px - crop_left_px;
        output_height = crop_bottom_px - crop_top_px;
        
        VLOG("vk_process_image_internal: Cropping to %dx%d (from %.2f,%.2f to %.2f,%.2f)\n",
             output_width, output_height, crop_left, crop_top, crop_right, crop_bottom);
    }
    
    // Calculate buffer sizes (ensure alignment for storage buffers)
    size_t input_pixel_count = width * height;
    size_t output_pixel_count = output_width * output_height;
    size_t input_size = input_pixel_count * 3;  // RGB
    size_t output_size = output_pixel_count * 4; // RGBA
    
    // Round up buffer sizes to multiple of 4 bytes for alignment
    size_t input_buffer_size = ((input_size + 3) / 4) * 4;
    size_t output_buffer_size = output_size; // Already aligned (4 bytes per pixel)
    size_t uniform_size = sizeof(float) * 20; // Adjustment parameters with crop (80 bytes)
    
    // Create buffers
    VkBuffer input_buffer, output_buffer, uniform_buffer;
    VkBuffer rgb_lut_buffer, red_lut_buffer, green_lut_buffer, blue_lut_buffer;
    VkDeviceMemory input_memory, output_memory, uniform_memory;
    VkDeviceMemory rgb_lut_memory, red_lut_memory, green_lut_memory, blue_lut_memory;
    
    VLOG("vk_process_image_internal: Creating buffers...\n");
    
    // Create input buffer (device local)
    VkBufferCreateInfo buffer_info = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = input_buffer_size,
        .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE
    };
    
    result = vkCreateBuffer(device, &buffer_info, NULL, &input_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (input)")) return 0;
    
    VLOG("vk_process_image_internal: Input buffer created\n");
    
    // Allocate memory for input buffer
    VkMemoryRequirements mem_reqs;
    vkGetBufferMemoryRequirements(device, input_buffer, &mem_reqs);
    
    VkMemoryAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_reqs.size,
        .memoryTypeIndex = find_memory_type(mem_reqs.memoryTypeBits, 
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    };
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &input_memory);
    if (!check_vk_result(result, "vkAllocateMemory (input)")) {
        vkDestroyBuffer(device, input_buffer, NULL);
        return 0;
    }
    
    vkBindBufferMemory(device, input_buffer, input_memory, 0);
    
    // Create output buffer
    buffer_info.size = output_buffer_size;
    buffer_info.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    
    result = vkCreateBuffer(device, &buffer_info, NULL, &output_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (output)")) {
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        return 0;
    }
    
    vkGetBufferMemoryRequirements(device, output_buffer, &mem_reqs);
    alloc_info.allocationSize = mem_reqs.size;
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &output_memory);
    if (!check_vk_result(result, "vkAllocateMemory (output)")) {
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        return 0;
    }
    
    vkBindBufferMemory(device, output_buffer, output_memory, 0);
    
    // Create uniform buffer (host visible for parameters)
    buffer_info.size = uniform_size;
    buffer_info.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    
    result = vkCreateBuffer(device, &buffer_info, NULL, &uniform_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (uniform)")) {
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        return 0;
    }
    
    vkGetBufferMemoryRequirements(device, uniform_buffer, &mem_reqs);
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = find_memory_type(mem_reqs.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &uniform_memory);
    if (!check_vk_result(result, "vkAllocateMemory (uniform)")) {
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        return 0;
    }
    
    vkBindBufferMemory(device, uniform_buffer, uniform_memory, 0);
    
    // Create tone curve LUT buffers (256 bytes each, aligned to 4)
    size_t lut_size = 256;
    buffer_info.size = lut_size;
    buffer_info.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    
    // RGB LUT buffer
    result = vkCreateBuffer(device, &buffer_info, NULL, &rgb_lut_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (rgb_lut)")) {
        processing = 0;
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    
    // Red LUT buffer
    result = vkCreateBuffer(device, &buffer_info, NULL, &red_lut_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (red_lut)")) {
        processing = 0;
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    
    // Green LUT buffer
    result = vkCreateBuffer(device, &buffer_info, NULL, &green_lut_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (green_lut)")) {
        processing = 0;
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    
    // Blue LUT buffer
    result = vkCreateBuffer(device, &buffer_info, NULL, &blue_lut_buffer);
    if (!check_vk_result(result, "vkCreateBuffer (blue_lut)")) {
        processing = 0;
        vkDestroyBuffer(device, green_lut_buffer, NULL);
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    
    // Allocate memory for LUT buffers
    vkGetBufferMemoryRequirements(device, rgb_lut_buffer, &mem_reqs);
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = find_memory_type(mem_reqs.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &rgb_lut_memory);
    if (!check_vk_result(result, "vkAllocateMemory (rgb_lut)")) {
        processing = 0;
        vkDestroyBuffer(device, blue_lut_buffer, NULL);
        vkDestroyBuffer(device, green_lut_buffer, NULL);
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    vkBindBufferMemory(device, rgb_lut_buffer, rgb_lut_memory, 0);
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &red_lut_memory);
    if (!check_vk_result(result, "vkAllocateMemory (red_lut)")) {
        processing = 0;
        vkFreeMemory(device, rgb_lut_memory, NULL);
        vkDestroyBuffer(device, blue_lut_buffer, NULL);
        vkDestroyBuffer(device, green_lut_buffer, NULL);
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    vkBindBufferMemory(device, red_lut_buffer, red_lut_memory, 0);
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &green_lut_memory);
    if (!check_vk_result(result, "vkAllocateMemory (green_lut)")) {
        processing = 0;
        vkFreeMemory(device, red_lut_memory, NULL);
        vkFreeMemory(device, rgb_lut_memory, NULL);
        vkDestroyBuffer(device, blue_lut_buffer, NULL);
        vkDestroyBuffer(device, green_lut_buffer, NULL);
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    vkBindBufferMemory(device, green_lut_buffer, green_lut_memory, 0);
    
    result = vkAllocateMemory(device, &alloc_info, NULL, &blue_lut_memory);
    if (!check_vk_result(result, "vkAllocateMemory (blue_lut)")) {
        processing = 0;
        vkFreeMemory(device, green_lut_memory, NULL);
        vkFreeMemory(device, red_lut_memory, NULL);
        vkFreeMemory(device, rgb_lut_memory, NULL);
        vkDestroyBuffer(device, blue_lut_buffer, NULL);
        vkDestroyBuffer(device, green_lut_buffer, NULL);
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    vkBindBufferMemory(device, blue_lut_buffer, blue_lut_memory, 0);
    
    // Copy LUT data to GPU
    void* mapped_lut;
    vkMapMemory(device, rgb_lut_memory, 0, lut_size, 0, &mapped_lut);
    memcpy(mapped_lut, rgb_lut, lut_size);
    vkUnmapMemory(device, rgb_lut_memory);
    
    vkMapMemory(device, red_lut_memory, 0, lut_size, 0, &mapped_lut);
    memcpy(mapped_lut, red_lut, lut_size);
    vkUnmapMemory(device, red_lut_memory);
    
    vkMapMemory(device, green_lut_memory, 0, lut_size, 0, &mapped_lut);
    memcpy(mapped_lut, green_lut, lut_size);
    vkUnmapMemory(device, green_lut_memory);
    
    vkMapMemory(device, blue_lut_memory, 0, lut_size, 0, &mapped_lut);
    memcpy(mapped_lut, blue_lut, lut_size);
    vkUnmapMemory(device, blue_lut_memory);
    
    VLOG("vk_process_image_internal: Tone curve LUTs uploaded\n");
    
    // Upload uniform data (adjustment parameters)
    void* mapped_uniform;
    vkMapMemory(device, uniform_memory, 0, uniform_size, 0, &mapped_uniform);
    
    // Pack adjustment parameters to match shader uniform structure
    float packed_params[20] = {0}; // Initialize all to 0 (now includes crop params)
    
    // Copy the adjustments
    int params_to_copy = (adjustment_count < 20) ? adjustment_count : 20;
    for (int i = 0; i < params_to_copy; i++) {
        packed_params[i] = adjustments[i];
    }
    
    // Always set image dimensions
    packed_params[11] = (float)width;   // imageWidth
    packed_params[12] = (float)height;  // imageHeight
    
    // If crop parameters weren't provided (adjustment_count < 18), set defaults
    if (adjustment_count < 15) packed_params[14] = 0.0f;  // cropLeft
    if (adjustment_count < 16) packed_params[15] = 0.0f;  // cropTop
    if (adjustment_count < 17) packed_params[16] = 1.0f;  // cropRight
    if (adjustment_count < 18) packed_params[17] = 1.0f;  // cropBottom
    
    VLOG("vk_process_image_internal: Params: temp=%.1f, exp=%.2f, width=%.0f, height=%.0f\n", 
         packed_params[0], packed_params[2], packed_params[11], packed_params[12]);
    
    memcpy(mapped_uniform, packed_params, sizeof(packed_params));
    vkUnmapMemory(device, uniform_memory);
    
    // Create staging buffer for input upload
    VkBuffer staging_in;
    VkDeviceMemory staging_in_memory;
    
    buffer_info.size = input_size;
    buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    
    vkCreateBuffer(device, &buffer_info, NULL, &staging_in);
    vkGetBufferMemoryRequirements(device, staging_in, &mem_reqs);
    
    alloc_info.allocationSize = mem_reqs.size;
    alloc_info.memoryTypeIndex = find_memory_type(mem_reqs.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    
    vkAllocateMemory(device, &alloc_info, NULL, &staging_in_memory);
    vkBindBufferMemory(device, staging_in, staging_in_memory, 0);
    
    // Upload input data
    void* mapped_input;
    vkMapMemory(device, staging_in_memory, 0, input_size, 0, &mapped_input);
    memcpy(mapped_input, input_pixels, input_size);
    vkUnmapMemory(device, staging_in_memory);
    
    // Create staging buffer for output download
    VkBuffer staging_out;
    VkDeviceMemory staging_out_memory;
    
    buffer_info.size = output_size;
    buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    
    vkCreateBuffer(device, &buffer_info, NULL, &staging_out);
    vkGetBufferMemoryRequirements(device, staging_out, &mem_reqs);
    
    alloc_info.allocationSize = mem_reqs.size;
    vkAllocateMemory(device, &alloc_info, NULL, &staging_out_memory);
    vkBindBufferMemory(device, staging_out, staging_out_memory, 0);
    
    // Create descriptor set
    VkDescriptorSet descriptor_set;
    VkDescriptorSetAllocateInfo desc_alloc_info = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &descriptor_set_layout
    };
    
    vkAllocateDescriptorSets(device, &desc_alloc_info, &descriptor_set);
    
    // Update descriptor set
    VkDescriptorBufferInfo buffer_infos[] = {
        { .buffer = input_buffer, .offset = 0, .range = VK_WHOLE_SIZE },
        { .buffer = output_buffer, .offset = 0, .range = VK_WHOLE_SIZE },
        { .buffer = uniform_buffer, .offset = 0, .range = uniform_size },
        { .buffer = rgb_lut_buffer, .offset = 0, .range = lut_size },
        { .buffer = red_lut_buffer, .offset = 0, .range = lut_size },
        { .buffer = green_lut_buffer, .offset = 0, .range = lut_size },
        { .buffer = blue_lut_buffer, .offset = 0, .range = lut_size }
    };
    
    VkWriteDescriptorSet writes[] = {
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buffer_infos[0]
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 1,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buffer_infos[1]
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 2,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pBufferInfo = &buffer_infos[2]
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 3,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buffer_infos[3]
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 4,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buffer_infos[4]
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 5,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buffer_infos[5]
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_set,
            .dstBinding = 6,
            .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .pBufferInfo = &buffer_infos[6]
        }
    };
    
    vkUpdateDescriptorSets(device, 7, writes, 0, NULL);
    
    VLOG("vk_process_image_internal: Recording command buffer...\n");
    
    // Record and execute command buffer
    VkCommandBufferBeginInfo begin_info = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };
    
    result = vkBeginCommandBuffer(command_buffer, &begin_info);
    if (!check_vk_result(result, "vkBeginCommandBuffer")) {
        // Cleanup and return
        vkDestroyBuffer(device, staging_in, NULL);
        vkFreeMemory(device, staging_in_memory, NULL);
        vkDestroyBuffer(device, staging_out, NULL);
        vkFreeMemory(device, staging_out_memory, NULL);
        vkDestroyBuffer(device, input_buffer, NULL);
        vkFreeMemory(device, input_memory, NULL);
        vkDestroyBuffer(device, output_buffer, NULL);
        vkFreeMemory(device, output_memory, NULL);
        vkDestroyBuffer(device, uniform_buffer, NULL);
        vkFreeMemory(device, uniform_memory, NULL);
        return 0;
    }
    
    VLOG("vk_process_image_internal: Command buffer recording started\n");
    
    // Copy input data from staging to device
    VkBufferCopy copy_region = { .size = input_size };
    vkCmdCopyBuffer(command_buffer, staging_in, input_buffer, 1, &copy_region);
    
    // Memory barrier before compute
    VkMemoryBarrier barrier = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_SHADER_READ_BIT
    };
    
    vkCmdPipelineBarrier(command_buffer,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        0, 1, &barrier, 0, NULL, 0, NULL);
    
    // Bind pipeline and descriptor set
    vkCmdBindPipeline(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE, compute_pipeline);
    vkCmdBindDescriptorSets(command_buffer, VK_PIPELINE_BIND_POINT_COMPUTE,
        pipeline_layout, 0, 1, &descriptor_set, 0, NULL);
    
    // Dispatch compute shader (16x16 workgroups) based on output dimensions
    uint32_t group_count_x = (output_width + 15) / 16;
    uint32_t group_count_y = (output_height + 15) / 16;
    vkCmdDispatch(command_buffer, group_count_x, group_count_y, 1);
    
    // Memory barrier after compute
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    
    vkCmdPipelineBarrier(command_buffer,
        VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 1, &barrier, 0, NULL, 0, NULL);
    
    // Copy output data from device to staging
    copy_region.size = output_size;
    vkCmdCopyBuffer(command_buffer, output_buffer, staging_out, 1, &copy_region);
    
    vkEndCommandBuffer(command_buffer);
    
    // Submit command buffer
    VkSubmitInfo submit_info = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &command_buffer
    };
    
    vkQueueSubmit(compute_queue, 1, &submit_info, VK_NULL_HANDLE);
    vkQueueWaitIdle(compute_queue);
    
    // Download output data
    *output_pixels = (uint8_t*)malloc(output_size);
    void* mapped_output;
    vkMapMemory(device, staging_out_memory, 0, output_size, 0, &mapped_output);
    memcpy(*output_pixels, mapped_output, output_size);
    vkUnmapMemory(device, staging_out_memory);
    
    // Cleanup
    vkDestroyBuffer(device, staging_in, NULL);
    vkFreeMemory(device, staging_in_memory, NULL);
    vkDestroyBuffer(device, staging_out, NULL);
    vkFreeMemory(device, staging_out_memory, NULL);
    vkDestroyBuffer(device, input_buffer, NULL);
    vkFreeMemory(device, input_memory, NULL);
    vkDestroyBuffer(device, output_buffer, NULL);
    vkFreeMemory(device, output_memory, NULL);
    vkDestroyBuffer(device, uniform_buffer, NULL);
    vkFreeMemory(device, uniform_memory, NULL);
    
    // Clean up tone curve LUT buffers if they were created
    if (rgb_lut != NULL) {
        vkDestroyBuffer(device, rgb_lut_buffer, NULL);
        vkFreeMemory(device, rgb_lut_memory, NULL);
        vkDestroyBuffer(device, red_lut_buffer, NULL);
        vkFreeMemory(device, red_lut_memory, NULL);
        vkDestroyBuffer(device, green_lut_buffer, NULL);
        vkFreeMemory(device, green_lut_memory, NULL);
        vkDestroyBuffer(device, blue_lut_buffer, NULL);
        vkFreeMemory(device, blue_lut_memory, NULL);
    }
    
    // Free descriptor set
    vkFreeDescriptorSets(device, descriptor_pool, 1, &descriptor_set);
    
    vkResetCommandBuffer(command_buffer, 0);
    
    processing = 0; // Clear processing flag
    VLOG("vk_process_image_internal: Complete\n");
    return 1;
}

// Process image with tone curves support
int vk_process_image_with_curves(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    const uint8_t* rgb_lut,
    const uint8_t* red_lut,
    const uint8_t* green_lut,
    const uint8_t* blue_lut,
    uint8_t** output_pixels
) {
    return vk_process_image_internal(
        input_pixels, width, height,
        adjustments, adjustment_count,
        rgb_lut, red_lut, green_lut, blue_lut,
        output_pixels
    );
}

int vk_process_image_with_curves_and_crop(
    const uint8_t* input_pixels,
    int width,
    int height,
    const float* adjustments,
    int adjustment_count,
    float crop_left,
    float crop_top,
    float crop_right,
    float crop_bottom,
    const uint8_t* rgb_lut,
    const uint8_t* red_lut,
    const uint8_t* green_lut,
    const uint8_t* blue_lut,
    uint8_t** output_pixels,
    int* output_width,
    int* output_height
) {
    // Validate crop parameters
    if (crop_left < 0.0f) crop_left = 0.0f;
    if (crop_top < 0.0f) crop_top = 0.0f;
    if (crop_right > 1.0f) crop_right = 1.0f;
    if (crop_bottom > 1.0f) crop_bottom = 1.0f;
    if (crop_left >= crop_right || crop_top >= crop_bottom) {
        // Invalid crop, use full image
        crop_left = 0.0f;
        crop_top = 0.0f;
        crop_right = 1.0f;
        crop_bottom = 1.0f;
    }
    
    // Calculate output dimensions
    // Match CPU's approach: round to pixels first, then subtract
    int crop_left_px = (int)round(crop_left * width);
    int crop_top_px = (int)round(crop_top * height);
    int crop_right_px = (int)round(crop_right * width);
    int crop_bottom_px = (int)round(crop_bottom * height);
    
    *output_width = crop_right_px - crop_left_px;
    *output_height = crop_bottom_px - crop_top_px;
    
    fprintf(stderr, "DEBUG vk_process_image_with_curves_and_crop:\n");
    fprintf(stderr, "  Input: %dx%d\n", width, height);
    fprintf(stderr, "  Crop: %.4f,%.4f to %.4f,%.4f\n", crop_left, crop_top, crop_right, crop_bottom);
    fprintf(stderr, "  Pixels: left=%d, top=%d, right=%d, bottom=%d\n", 
            crop_left_px, crop_top_px, crop_right_px, crop_bottom_px);
    fprintf(stderr, "  Output: %dx%d\n", *output_width, *output_height);
    
    // Create extended adjustments array with crop parameters
    // We need 18 floats total (14 base + 4 crop parameters)
    float* extended_adjustments = (float*)malloc(sizeof(float) * 18);
    if (!extended_adjustments) {
        fprintf(stderr, "Failed to allocate extended adjustments\n");
        return 0;
    }
    
    // Copy original adjustments
    memcpy(extended_adjustments, adjustments, sizeof(float) * adjustment_count);
    
    // Ensure we have at least 14 floats (pad with zeros if needed)
    for (int i = adjustment_count; i < 14; i++) {
        extended_adjustments[i] = 0.0f;
    }
    
    // Set image dimensions
    extended_adjustments[11] = (float)width;  // imageWidth
    extended_adjustments[12] = (float)height; // imageHeight
    
    // Add crop parameters at indices 14-17
    extended_adjustments[14] = crop_left;
    extended_adjustments[15] = crop_top;
    extended_adjustments[16] = crop_right;
    extended_adjustments[17] = crop_bottom;
    
    int result = vk_process_image_internal(
        input_pixels, width, height,
        extended_adjustments, 18,
        rgb_lut, red_lut, green_lut, blue_lut,
        output_pixels
    );
    
    free(extended_adjustments);
    return result;
}

void vk_free_buffer(uint8_t* buffer) {
    free(buffer);
}

void vk_cleanup() {
    if (!initialized) return;
    
    if (device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(device);
        
        if (command_pool != VK_NULL_HANDLE) {
            vkDestroyCommandPool(device, command_pool, NULL);
        }
        
        if (descriptor_pool != VK_NULL_HANDLE) {
            vkDestroyDescriptorPool(device, descriptor_pool, NULL);
        }
        
        if (compute_shader_module != VK_NULL_HANDLE) {
            vkDestroyShaderModule(device, compute_shader_module, NULL);
        }
        
        if (compute_pipeline != VK_NULL_HANDLE) {
            vkDestroyPipeline(device, compute_pipeline, NULL);
        }
        
        if (pipeline_layout != VK_NULL_HANDLE) {
            vkDestroyPipelineLayout(device, pipeline_layout, NULL);
        }
        
        if (descriptor_set_layout != VK_NULL_HANDLE) {
            vkDestroyDescriptorSetLayout(device, descriptor_set_layout, NULL);
        }
        
        vkDestroyDevice(device, NULL);
    }
    
    if (instance != VK_NULL_HANDLE) {
        vkDestroyInstance(instance, NULL);
    }
    
    initialized = 0;
}