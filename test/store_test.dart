import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/models.dart';
import 'package:mwomeogeo/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MealStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('mwomeogeo-test-');
    store = MealStore(await SharedPreferences.getInstance(), directory);
    await store.load();
  });
  tearDown(() async {
    await directory.delete(recursive: true);
    store.dispose();
  });
  test(
    'a saved photo survives temporary camera file deletion and app restart',
    () async {
      final camera = File('${directory.path}/camera.jpg');
      await camera.writeAsBytes([1, 2, 3, 4]);
      await store.setName('채은');
      await store.saveMeal(
        source: camera,
        meal: 1,
        caption: '잘 먹었어',
        tableIds: ['local-couple', 'local-family'],
      );
      await camera.delete();
      final restarted = MealStore(
        await SharedPreferences.getInstance(),
        directory,
      );
      await restarted.load();
      expect(restarted.demo, false);
      expect(restarted.localPosts.length, 1);
      final post = restarted.localPosts.single;
      expect(await File('${directory.path}/${post.photo}').readAsBytes(), [
        1,
        2,
        3,
        4,
      ]);
      expect(post.author, '채은');
      expect(post.caption, '잘 먹었어');
      restarted.selectTable('local-family');
      expect(restarted.postsOn(DateTime.now(), meal: 1).single.id, post.id);
      restarted.dispose();
    },
  );
  test('reactions and per-post comments survive a restart and toggle independently', () async {
    final camera = File('${directory.path}/camera.jpg');
    await camera.writeAsBytes([1]);
    await store.saveMeal(
      source: camera,
      meal: 0,
      caption: '',
      tableIds: ['local-couple'],
    );
    final post = store.localPosts.single;
    await store.react(post, 'heart');
    await store.react(post, 'yum');
    await store.react(post, 'heart');
    await store.addComment(post, '아침도 챙겨 먹자');
    final restarted = MealStore(
      await SharedPreferences.getInstance(),
      directory,
    );
    await restarted.load();
    expect(restarted.localPosts.single.reactions, {'local:yum'});
    expect(restarted.localPosts.single.comments.single.text, '아침도 챙겨 먹자');
    restarted.dispose();
  });
  test(
    'deleting a local post removes its metadata and private photo',
    () async {
      final camera = File('${directory.path}/camera.jpg');
      await camera.writeAsBytes([1]);
      await store.saveMeal(
        source: camera,
        meal: 2,
        caption: '',
        tableIds: ['local-family'],
      );
      final post = store.localPosts.single;
      final photo = File('${directory.path}/${post.photo}');
      await store.delete(post);
      expect(store.localPosts, isEmpty);
      expect(await photo.exists(), false);
      final restarted = MealStore(
        await SharedPreferences.getInstance(),
        directory,
      );
      await restarted.load();
      expect(restarted.localPosts, isEmpty);
      restarted.dispose();
    },
  );
  test('calendar dates do not mix years or adjacent months', () {
    expect(sameDay(DateTime(2026, 10, 20), DateTime(2026, 10, 20, 23)), true);
    expect(sameDay(DateTime(2026, 10, 20), DateTime(2025, 10, 20)), false);
    expect(sameDay(DateTime(2026, 10, 20), DateTime(2026, 11, 20)), false);
    store.localPosts.add(
      MealPost(
        id: newId(),
        author: '나',
        photo: 'test.jpg',
        meal: 1,
        date: DateTime(2026, 9, 20),
        tableIds: ['local-couple'],
      ),
    );
    expect(store.postsOn(DateTime(2026, 9, 20)).single.isDemo, false);
    expect(store.postsOn(DateTime(2026, 11, 20)), isEmpty);
  });
  test(
    'preview reactions are visible only in the preview and never persisted',
    () async {
      final sample = store.postsOn(DateTime.now(), meal: 1).first;
      await store.react(sample, 'heart');
      expect(
        store.postsOn(DateTime.now(), meal: 1).first.reactions,
        contains('local:heart'),
      );
      await store.setDemo(false);
      expect(store.postsOn(DateTime.now()), isEmpty);
      expect(store.preferences.getString('posts'), isNull);
    },
  );
}
