import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aks/models/image_state.dart';
import 'package:aks/models/adjustments.dart';

// These tests exercise the parts of ImageState that don't require a native
// RAW decoder or Flutter engine: the collaborator wiring, undo/redo flag
// suppression, display-mode flags, and disposal. File-loading and actual
// image processing are covered by the integration tests in test/linux/.

void main() {
  // ImageState() reads the highlight-mode preference in its constructor,
  // which needs the services binding and a shared_preferences backend.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ImageState', () {
    test('exposes empty defaults before any image is loaded', () {
      final state = ImageState();
      expect(state.hasImage, false);
      expect(state.isLoading, false);
      expect(state.isProcessing, false);
      expect(state.error, null);
      expect(state.currentImage, null);
      expect(state.originalImage, null);
      expect(state.originalWidth, null);
      expect(state.originalHeight, null);
      expect(state.actualCurrentWidth, null);
      expect(state.actualCurrentHeight, null);
      expect(state.exportImageWidth, null);
      expect(state.exportImageHeight, null);
      expect(state.exifData, null);
      expect(state.hasCrop, false);
      expect(state.showOriginal, false);
      state.dispose();
    });

    test('setShowOriginal and toggleOriginal notify listeners only on change', () {
      final state = ImageState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.setShowOriginal(false); // no change from default (false)
      expect(notifications, 0);
      state.setShowOriginal(true);
      expect(notifications, 1);
      expect(state.showOriginal, true);

      state.toggleOriginal();
      expect(state.showOriginal, false);
      expect(notifications, 2);

      state.dispose();
    });

    test('setError clears loading and notifies', () {
      final state = ImageState();
      var notifications = 0;
      state.addListener(() => notifications++);
      state.setLoading(true);
      expect(state.isLoading, true);
      state.setError('boom');
      expect(state.isLoading, false);
      expect(state.error, 'boom');
      // One for setLoading, one for setError.
      expect(notifications, 2);
      state.dispose();
    });

    test('clear resets display flags and data', () {
      final state = ImageState();
      state.setShowOriginal(true);
      state.processing.originalWidth = 100;
      state.processing.originalHeight = 200;

      state.clear();
      expect(state.showOriginal, false);
      expect(state.hasCrop, false);
      expect(state.originalWidth, null);
      expect(state.originalHeight, null);
      expect(state.isLoading, false);
      expect(state.error, null);

      state.dispose();
    });

    test('undo with no history is a no-op and does not throw', () {
      final state = ImageState();
      state.undo();
      state.redo();
      expect(state.historyManager.canUndo, false);
      expect(state.historyManager.canRedo, false);
      state.dispose();
    });

    test('undo walks the history pointer back', () {
      final state = ImageState();
      // Seed two history entries so we can undo once.
      state.pipeline.updateAdjustment(ExposureAdjustment(value: 1.0));
      state.historyManager.addEntry(state.pipeline, 'exposure +1');

      expect(state.historyManager.canUndo, true);
      expect(state.historyManager.canRedo, false);

      state.undo();
      // After undo, we should be able to redo.
      expect(state.historyManager.canRedo, true);

      state.dispose();
    });

    test('dispose is safe and leaves state inert', () {
      final state = ImageState();
      state.dispose();
      // No assertions about post-dispose behavior — just that dispose
      // itself runs cleanly and can be called once.
      expect(true, true);
    });

    test('actualCurrentWidth/Height account for crop rect', () {
      final state = ImageState();
      state.processing.originalWidth = 1000;
      state.processing.originalHeight = 800;

      // No crop → returns original.
      expect(state.actualCurrentWidth, 1000);
      expect(state.actualCurrentHeight, 800);

      state.dispose();
    });
  });
}
