#include <turbojpeg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "jpeg_binding.h"

extern "C" {
    void* jpeg_compress_init(int width, int height, int quality) {
        tjhandle handle = tjInitCompress();
        if (!handle) return NULL;
        
        // Store parameters in the handle
        int* params = (int*)malloc(sizeof(int) * 3);
        params[0] = width;
        params[1] = height;
        params[2] = quality;
        
        return (void*)params;
    }
    
    JpegBuffer jpeg_compress_rgb(void* handle, uint8_t* rgb_data) {
        JpegBuffer result = {NULL, 0};
        int* params = (int*)handle;
        int width = params[0];
        int height = params[1];
        int quality = params[2];
        
        tjhandle jpeg_handle = tjInitCompress();
        if (!jpeg_handle) return result;
        
        unsigned long jpeg_size = tjBufSize(width, height, TJSAMP_420);
        unsigned char* jpeg_buf = (unsigned char*)malloc(jpeg_size);
        
        int success = tjCompress2(
            jpeg_handle,
            rgb_data,
            width,
            width * 3,
            height,
            TJPF_RGB,
            &jpeg_buf,
            &jpeg_size,
            TJSAMP_420,
            quality,
            TJFLAG_FASTDCT
        );
        
        if (success == 0) {
            result.data = jpeg_buf;
            result.size = jpeg_size;
        } else {
            free(jpeg_buf);
        }
        
        tjDestroy(jpeg_handle);
        return result;
    }
    
    JpegBuffer jpeg_compress_rgba(void* handle, uint8_t* rgba_data) {
        JpegBuffer result = {NULL, 0};
        int* params = (int*)handle;
        int width = params[0];
        int height = params[1];
        int quality = params[2];
        
        tjhandle jpeg_handle = tjInitCompress();
        if (!jpeg_handle) return result;
        
        unsigned long jpeg_size = tjBufSize(width, height, TJSAMP_420);
        unsigned char* jpeg_buf = (unsigned char*)malloc(jpeg_size);
        
        int success = tjCompress2(
            jpeg_handle,
            rgba_data,
            width,
            width * 4,
            height,
            TJPF_RGBA,
            &jpeg_buf,
            &jpeg_size,
            TJSAMP_420,
            quality,
            TJFLAG_FASTDCT
        );
        
        if (success == 0) {
            result.data = jpeg_buf;
            result.size = jpeg_size;
        } else {
            free(jpeg_buf);
        }
        
        tjDestroy(jpeg_handle);
        return result;
    }
    
    void jpeg_free_buffer(JpegBuffer buffer) {
        if (buffer.data) {
            free(buffer.data);
        }
    }
    
    void jpeg_compress_cleanup(void* handle) {
        if (handle) {
            free(handle);
        }
    }
}