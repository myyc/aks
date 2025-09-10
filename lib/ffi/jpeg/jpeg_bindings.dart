import 'dart:ffi';
import 'package:ffi/ffi.dart';

// JPEG FFI bindings
base class JpegBuffer extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int size;
}

class JpegBindings {
  final DynamicLibrary _lib;
  
  JpegBindings(this._lib);
  
  late final _jpeg_compress_init = _lib.lookupFunction<
      Pointer<Void> Function(Int32, Int32, Int32),
      Pointer<Void> Function(int, int, int)>('jpeg_compress_init');
  
  late final _jpeg_compress_rgb = _lib.lookupFunction<
      JpegBuffer Function(Pointer<Void>, Pointer<Uint8>),
      JpegBuffer Function(Pointer<Void>, Pointer<Uint8>)>('jpeg_compress_rgb');
  
  late final _jpeg_compress_rgba = _lib.lookupFunction<
      JpegBuffer Function(Pointer<Void>, Pointer<Uint8>),
      JpegBuffer Function(Pointer<Void>, Pointer<Uint8>)>('jpeg_compress_rgba');
  
  late final _jpeg_free_buffer = _lib.lookupFunction<
      Void Function(JpegBuffer),
      void Function(JpegBuffer)>('jpeg_free_buffer');
  
  late final _jpeg_compress_cleanup = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('jpeg_compress_cleanup');
  
  Pointer<Void> jpegCompressInit(int width, int height, int quality) {
    return _jpeg_compress_init(width, height, quality);
  }
  
  JpegBuffer jpegCompressRgba(Pointer<Void> handle, Pointer<Uint8> rgbaData) {
    return _jpeg_compress_rgba(handle, rgbaData);
  }
  
  void jpegFreeBuffer(JpegBuffer buffer) {
    _jpeg_free_buffer(buffer);
  }
  
  void jpegCompressCleanup(Pointer<Void> handle) {
    _jpeg_compress_cleanup(handle);
  }
}