import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/models.dart';
import 'package:mwomeogeo/store.dart';
import 'package:mwomeogeo/rice_stickers.dart';

void main() {
  test(
    'old posts and sticker placement round trip without modifying photo',
    () {
      final post = demoPosts(DateTime(2026, 11, 9)).first;
      final old = post.toJson()..remove('stickers');
      expect(MealPost.fromJson(old).stickers, isEmpty);
      post.stickers.add(const RiceSticker('local', '채은', 2, .8, .7, .24));
      final restored = MealPost.fromJson(post.toJson());
      expect(restored.photo, post.photo);
      expect(restored.caption, post.caption);
      expect(restored.stickers.single.x, .8);
      expect(restored.stickers.single.variant, 2);
    },
  );
  testWidgets(
    'partner sticker picker saves, replaces and removes own overlay',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('rice-sticker-'),
      ))!;
      final store = MealStore(await SharedPreferences.getInstance(), dir);
      final post = demoPosts(DateTime.now()).first;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editRiceSticker(context, post, store),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('하트'));
      await tester.tap(find.text('하트'));
      await tester.pump();
      await tester.ensureVisible(find.text('붙이기'));
      await tester.tap(find.text('붙이기'));
      await tester.pumpAndSettle();
      expect(post.stickers.single.variant, 2);
      await store.putSticker(
        post,
        const RiceSticker('local', '채은', 0, .3, .4, .2),
      );
      expect(post.stickers.length, 1);
      expect(post.stickers.single.variant, 0);
      await store.putSticker(post, null);
      expect(post.stickers, isEmpty);
      store.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
