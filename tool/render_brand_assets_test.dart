// Run with: CI=true flutter test --no-pub tool/render_brand_assets_test.dart
// Export the same Canvas artwork used by the app, then run pack_brand_assets.py.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwomeogeo/app_icons.dart';

void main() {
  testWidgets('export rice friends brand artwork', (tester) async {
    await tester.runAsync(() async {
      Future<void> export(
        String path,
        int pixels,
        void Function(Canvas) draw,
      ) async {
        final recorder = ui.PictureRecorder();
        draw(Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(pixels, pixels);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }

      await export('assets/app-icon.png', 1024, (canvas) {
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 1024, 1024),
          Paint()..color = const Color(0xffffe7da),
        );
        canvas.translate(102, 102);
        const RiceFriendsPainter().paint(canvas, const Size(820, 820));
      });
      await export('assets/brand/rice-friends.png', 1024, (canvas) {
        const RiceFriendsPainter().paint(canvas, const Size(1024, 1024));
      });
      await export('assets/brand/camera.png', 256, (canvas) {
        const MealIconPainter(
          MealGlyph.camera,
          null,
          true,
        ).paint(canvas, const Size(256, 256));
      });
    });
  });
}
