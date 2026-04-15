import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/models/image_cache_bundle.dart';

Future<ui.Image> _tinyImage() async {
  final pixels = Uint8List.fromList([255, 0, 0, 255]);
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: 1,
    height: 1,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageCacheBundle', () {
    test('starts empty', () {
      final cache = ImageCacheBundle();
      expect(cache.hasImage, false);
      expect(cache.preview, null);
      expect(cache.full, null);
      expect(cache.currentImage(showOriginal: false), null);
      expect(cache.currentImage(showOriginal: true), null);
    });

    test('setting preview disposes the old reference', () async {
      final cache = ImageCacheBundle();
      final first = await _tinyImage();
      final second = await _tinyImage();

      cache.preview = first;
      expect(first.debugDisposed, false);

      cache.preview = second;
      expect(first.debugDisposed, true);
      expect(second.debugDisposed, false);
      expect(cache.preview, same(second));
    });

    test('assigning the same image twice does not dispose it', () async {
      final cache = ImageCacheBundle();
      final img = await _tinyImage();
      cache.preview = img;
      cache.preview = img;
      expect(img.debugDisposed, false);
    });

    test('currentImage falls back across resolutions', () async {
      final cache = ImageCacheBundle();
      final preview = await _tinyImage();
      final full = await _tinyImage();

      cache.preview = preview;
      cache.setUsePreview(true);
      expect(cache.currentImage(showOriginal: false), same(preview));

      cache.setUsePreview(false);
      expect(cache.currentImage(showOriginal: false), same(preview)); // full is null, falls back

      cache.full = full;
      expect(cache.currentImage(showOriginal: false), same(full));
    });

    test('currentImage respects showOriginal', () async {
      final cache = ImageCacheBundle();
      final preview = await _tinyImage();
      final originalPreview = await _tinyImage();

      cache.preview = preview;
      cache.originalPreview = originalPreview;

      expect(cache.currentImage(showOriginal: false), same(preview));
      expect(cache.currentImage(showOriginal: true), same(originalPreview));
    });

    test('setUsePreview reports whether the value changed', () {
      final cache = ImageCacheBundle();
      expect(cache.setUsePreview(true), false); // already true
      expect(cache.setUsePreview(false), true);
      expect(cache.setUsePreview(false), false);
    });

    test('clear disposes and nulls all four refs', () async {
      final cache = ImageCacheBundle();
      final a = await _tinyImage();
      final b = await _tinyImage();
      final c = await _tinyImage();
      final d = await _tinyImage();

      cache.preview = a;
      cache.full = b;
      cache.originalPreview = c;
      cache.originalFull = d;

      cache.clear();
      expect(a.debugDisposed, true);
      expect(b.debugDisposed, true);
      expect(c.debugDisposed, true);
      expect(d.debugDisposed, true);
      expect(cache.hasImage, false);
    });

    test('dispose is idempotent', () async {
      final cache = ImageCacheBundle();
      final img = await _tinyImage();
      cache.preview = img;
      cache.dispose();
      cache.dispose();
      expect(img.debugDisposed, true);
      expect(cache.preview, null);
    });
  });
}
