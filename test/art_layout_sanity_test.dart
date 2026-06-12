import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_editor/screen/collage/collage_models.dart';

void main() {
  test('every artistic layout has a path builder per cell', () {
    for (final layout in kArtisticLayouts) {
      final builders = kArtisticCellPaths[layout.id];
      expect(builders, isNotNull, reason: layout.id);
      expect(builders!.length, layout.cellCount, reason: layout.id);
    }
  });

  test('every shape layout renders through the artistic pipeline', () {
    const size = Size(900, 1600);
    for (final layout in kShapeLayouts) {
      expect(layout.isArtistic, isTrue, reason: layout.id);
      final builders = kArtisticCellPaths[layout.id];
      expect(builders, isNotNull, reason: layout.id);
      expect(builders!.length, layout.cellCount, reason: layout.id);
      for (final b in builders) {
        // A real shape path, not the full-canvas fallback rect.
        final bounds = b(size).getBounds();
        expect(bounds.isEmpty, isFalse, reason: layout.id);
        expect(bounds.width < size.width || bounds.height < size.height,
            isTrue, reason: '${layout.id} fell back to the default rect');
      }
    }
  });

  test('adjustable layouts: handles, param counts and builders are consistent',
      () {
    const size = Size(900, 1600);
    for (final entry in kArtisticAdjustablePaths.entries) {
      final id = entry.key;
      final handles = kArtisticHandles[id];
      expect(handles, isNotNull, reason: '$id has no handle definitions');

      final paramCount = artParamCount(id);
      expect(paramCount, greaterThan(0), reason: id);

      // Every param index must be reachable by exactly the offsets list the
      // editor will allocate — builders must not index past paramCount.
      final offsets = List<double>.filled(paramCount, 0.0);
      for (final b in entry.value) {
        final path = b(size, offsets);
        expect(path.getBounds().isEmpty, isFalse, reason: id);
      }

      // Non-zero offsets must also produce valid paths inside the canvas.
      final shifted = List<double>.filled(paramCount, 0.05);
      for (final b in entry.value) {
        final bounds = b(size, shifted).getBounds();
        expect(bounds.left, greaterThanOrEqualTo(-1), reason: id);
        expect(bounds.top, greaterThanOrEqualTo(-1), reason: id);
        expect(bounds.right, lessThanOrEqualTo(size.width + 1), reason: id);
        expect(bounds.bottom, lessThanOrEqualTo(size.height + 1), reason: id);
      }

      // Handle param indices must be within the allocated offsets list.
      for (final h in handles!) {
        expect(h.px, lessThan(paramCount), reason: id);
        expect(h.py, lessThan(paramCount), reason: id);
      }
    }
  });

  test('zero offsets reproduce the same shape as the default map', () {
    const size = Size(900, 1600);
    for (final entry in kArtisticAdjustablePaths.entries) {
      final defaults = kArtisticCellPaths[entry.key]!;
      final offsets = List<double>.filled(artParamCount(entry.key), 0.0);
      for (int i = 0; i < entry.value.length; i++) {
        final a = entry.value[i](size, offsets).getBounds();
        final b = defaults[i](size).getBounds();
        expect(a, b, reason: '${entry.key} cell $i');
      }
    }
  });
}
