import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/models.dart';
import 'package:mwomeogeo/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MealStore store;
  late String couple;
  late String family;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('mwomeogeo-test-');
    store = MealStore(await SharedPreferences.getInstance(), directory);
    await store.load();
    await store.createLocalTable('우리 둘');
    couple = store.tableId;
    await store.createLocalTable('가족 식탁');
    family = store.tableId;
    store.selectTable(couple);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
    store.dispose();
  });
  test(
    'fresh install and old preview preference start with zero rooms',
    () async {
      SharedPreferences.setMockInitialValues({
        'demo': true,
        'selectedTable': 'local-couple',
      });
      final fresh = MealStore(await SharedPreferences.getInstance(), directory);
      await fresh.load();
      expect(fresh.tables, isEmpty);
      expect(fresh.table, isNull);
      expect(fresh.allPosts, isEmpty);
      expect(fresh.demo, false);
      await fresh.createLocalTable('첫 식탁');
      expect(fresh.tables.single.name, '첫 식탁');
      final restored = MealStore(
        await SharedPreferences.getInstance(),
        directory,
      );
      await restored.load();
      expect(restored.tables.single.name, '첫 식탁');
      expect(restored.tableId, fresh.tableId);
      fresh.dispose();
      restored.dispose();
    },
  );
  test(
    'old records retain their room without adding the unused starter room',
    () async {
      final legacy = MealPost(
        id: 'old',
        author: '나',
        photo: 'old.jpg',
        meal: 1,
        date: DateTime.now(),
        tableIds: ['local-family'],
        caption: '기존 기록',
      );
      SharedPreferences.setMockInitialValues({
        'demo': true,
        'selectedTable': 'local-family',
        'posts': jsonEncode([legacy.toJson()]),
      });
      final restored = MealStore(
        await SharedPreferences.getInstance(),
        directory,
      );
      await restored.load();
      expect(restored.tables.single.id, 'local-family');
      expect(restored.postsOn(DateTime.now()).single.caption, '기존 기록');
      restored.dispose();
    },
  );
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
        tableIds: [couple, family],
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
      restarted.selectTable(family);
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
      tableIds: [couple],
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
        tableIds: [family],
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
        tableIds: [couple],
      ),
    );
    expect(store.postsOn(DateTime(2026, 9, 20)).single.isDemo, false);
    expect(store.postsOn(DateTime(2026, 11, 20)), isEmpty);
  });
  test(
    'preview reactions are visible only in the preview and never persisted',
    () async {
      await store.setDemo(true);
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
