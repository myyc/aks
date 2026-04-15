import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aks/models/edit_pipeline.dart';
import 'package:aks/services/processing_pipeline.dart';

// None of these tests put rawData/previewData/originalRawData/originalPreviewData
// into the pipeline. That short-circuits processFullResolution /
// processOriginalFull at their `== null` guard before any processor would be
// invoked — so the callbacks are harmless if they do fire, but the
// expectations assert that onReady never fires because we cancel first.

void main() {
  group('ProcessingPipeline', () {
    test('starts with no data and no flags', () {
      final p = ProcessingPipeline();
      expect(p.isProcessing, false);
      expect(p.rawData, null);
      expect(p.previewData, null);
    });

    test('clear cancels pending timers', () {
      fakeAsync((async) {
        final p = ProcessingPipeline();
        final pipeline = EditPipeline();
        var fired = 0;
        p.scheduleFullResProcessing(
          pipeline: pipeline,
          onReady: (_) => fired++,
        );
        p.scheduleOriginalFullProcessing(
          adjustmentsOnly: pipeline,
          onReady: (_) => fired++,
        );
        p.clear();
        async.elapse(const Duration(seconds: 5));
        expect(fired, 0);
      });
    });

    test('dispose cancels the original-full timer (line-406 regression)', () {
      // Models the pre-fix bug: a 500ms timer is armed, then the pipeline is
      // disposed before it fires. With the fix, the timer is cancelled.
      fakeAsync((async) {
        final p = ProcessingPipeline();
        final pipeline = EditPipeline();
        var fired = 0;
        p.scheduleOriginalFullProcessing(
          adjustmentsOnly: pipeline,
          onReady: (_) => fired++,
        );
        async.elapse(const Duration(milliseconds: 100));
        p.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(fired, 0);
      });
    });

    test('dispose is idempotent', () {
      final p = ProcessingPipeline();
      p.dispose();
      p.dispose();
      expect(p.isProcessing, false);
    });

    test('rescheduling the same timer replaces the previous one', () {
      fakeAsync((async) {
        final p = ProcessingPipeline();
        final pipeline = EditPipeline();
        var fired = 0;
        p.scheduleFullResProcessing(
          pipeline: pipeline,
          onReady: (_) => fired++,
        );
        async.elapse(const Duration(milliseconds: 500));
        // Reschedule before first fires. Original timer is cancelled.
        p.scheduleFullResProcessing(
          pipeline: pipeline,
          onReady: (_) => fired++,
        );
        async.elapse(const Duration(milliseconds: 500));
        // Original would have fired by now (total 1000ms since first schedule),
        // but it was cancelled. The rescheduled one has 500ms of its debounce
        // left and hasn't fired yet either.
        expect(fired, 0);
        p.cancelTimers();
        async.elapse(const Duration(seconds: 2));
        expect(fired, 0);
      });
    });
  });
}
