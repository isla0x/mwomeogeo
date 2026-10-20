import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'models.dart';

class MealStore extends ChangeNotifier {
  MealStore(this.preferences, this.directory);
  final SharedPreferences preferences;
  final Directory directory;
  final CloudApi cloud = CloudApi();
  StreamSubscription<List<DiningTable>>? _tablesSubscription;
  StreamSubscription<List<MealPost>>? _postsSubscription;
  String? _watchedTable;
  String? syncError;
  Future<void>? _connectionAttempt;
  final List<MealPost> previewPosts = demoPosts(DateTime.now());
  List<MealPost> localPosts = [];
  List<MealPost> remotePosts = [];
  List<DiningTable> remoteTables = [];
  bool demo = true;
  String name = '나';
  String tableId = 'local-couple';
  static const localTables = [
    DiningTable('local-couple', '우리 둘'),
    DiningTable('local-family', '가족 식탁'),
  ];
  List<DiningTable> get tables => [...localTables, ...remoteTables];
  DiningTable get table => tables.firstWhere(
    (g) => g.id == tableId,
    orElse: () => localTables.first,
  );
  List<MealPost> get allPosts => [
    ...localPosts,
    ...remotePosts,
    if (demo) ...previewPosts,
  ];
  List<MealPost> postsOn(DateTime date, {int? meal}) =>
      allPosts
          .where(
            (p) =>
                p.tableIds.contains(tableId) &&
                sameDay(p.date, date) &&
                (meal == null || p.meal == meal),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  Future<void> load() async {
    demo = preferences.getBool('demo') ?? true;
    name = preferences.getString('name') ?? '나';
    tableId = preferences.getString('selectedTable') ?? 'local-couple';
    final raw = preferences.getString('posts');
    if (raw != null) {
      localPosts = (jsonDecode(raw) as List)
          .map((j) => MealPost.fromJson(j))
          .toList();
    }
  }

  Future<void> _save() async {
    final ok = await preferences.setString(
      'posts',
      jsonEncode(localPosts.map((p) => p.toJson()).toList()),
    );
    if (!ok) throw const FileSystemException('기록을 저장하지 못했어요. 저장 공간을 확인해 주세요.');
  }

  Future<void> setDemo(bool value) async {
    await preferences.setBool('demo', value);
    demo = value;
    notifyListeners();
  }

  Future<void> setName(String value) async {
    await cloud.setDisplayName(value.trim());
    await preferences.setString('name', value.trim());
    name = value.trim();
    notifyListeners();
  }

  void selectTable(String id) {
    tableId = id;
    unawaited(preferences.setString('selectedTable', id));
    _watchSelectedTable();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!cloud.signedIn) return;
    final tables = await cloud.tables();
    final loaded = <MealPost>[];
    for (final table in tables) {
      loaded.addAll(await cloud.posts(table.id));
    }
    remoteTables = tables;
    remotePosts = loaded;
    syncError = null;
    _watchSelectedTable();
    notifyListeners();
  }

  Future<void> saveMeal({
    required File source,
    required int meal,
    required String caption,
    required List<String> tableIds,
  }) async {
    if (tableIds.isEmpty) throw ArgumentError('식탁을 선택해 주세요.');
    final local = tableIds.where((id) => id.startsWith('local-')).toList();
    final remote = tableIds.where((id) => !id.startsWith('local-')).toList();
    // Mixed local and remote destinations are disabled in the composer so a
    // failed upload cannot create a second local copy when the user retries.
    if (local.isNotEmpty && remote.isNotEmpty) {
      throw ArgumentError('기기 식탁과 함께 쓰는 식탁은 나누어 선택해 주세요.');
    }
    if (remote.isNotEmpty) {
      final delivered = await cloud.sendMeal(
        source,
        meal,
        caption,
        remote,
        name,
      );
      remotePosts.insertAll(0, delivered);
      // A completed delivery stays successful even if reloading the feed fails.
      try {
        await refresh();
      } catch (_) {}
    } else {
      final id = newId();
      final suffix = source.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final photo = 'photos/$id.$suffix';
      final dest = File('${directory.path}/$photo');
      await dest.parent.create(recursive: true);
      await source.copy(dest.path);
      final post = MealPost(
        id: id,
        author: name,
        photo: photo,
        meal: meal,
        date: DateTime.now(),
        tableIds: local,
        caption: caption,
      );
      localPosts.insert(0, post);
      try {
        await _save();
      } catch (_) {
        localPosts.remove(post);
        await dest.delete();
        rethrow;
      }
    }
    // A preview is explicit and never mixed into the user's own records.
    try {
      await preferences.setBool('demo', false);
    } catch (_) {}
    demo = false;
    selectTable(tableIds.first);
  }

  Future<void> react(MealPost post, String kind) async {
    if (post.isCloud) {
      await cloud.react(post, kind);
      await refresh();
      return;
    }
    final key = 'local:$kind';
    final selected = post.reactions.contains(key);
    if (selected) {
      post.reactions.remove(key);
    } else {
      post.reactions.add(key);
    }
    try {
      if (!post.isDemo) {
        await _save();
      }
    } catch (_) {
      if (selected) {
        post.reactions.add(key);
      } else {
        post.reactions.remove(key);
      }
      rethrow;
    }
    notifyListeners();
  }

  Future<void> addComment(MealPost post, String text) async {
    if (post.isCloud) {
      await cloud.comment(post, text);
      await refresh();
      return;
    }
    final comment = MealComment(name, text);
    post.comments.add(comment);
    try {
      if (!post.isDemo) {
        await _save();
      }
    } catch (_) {
      post.comments.remove(comment);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> delete(MealPost post) async {
    if (post.isCloud) {
      await cloud.deletePost(post);
      await refresh();
      return;
    }
    final index = localPosts.indexOf(post);
    if (index < 0) return;
    localPosts.removeAt(index);
    try {
      await _save();
    } catch (_) {
      localPosts.insert(index, post);
      rethrow;
    }
    // File cleanup is best effort after the record has been saved successfully.
    final file = File('${directory.path}/${post.photo}');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> connect() => _connectionAttempt ??= _connect().whenComplete(
    () => _connectionAttempt = null,
  );

  Future<void> _connect() async {
    await cloud.ensureIdentity(name);
    if (preferences.getString('name') == null && cloud.displayName != null) {
      name = cloud.displayName!;
    }
    await refresh();
    if (preferences.getString('selectedTable') == null &&
        remoteTables.isNotEmpty) {
      selectTable(remoteTables.first.id);
      await setDemo(false);
    }
    await _tablesSubscription?.cancel();
    _tablesSubscription = cloud.watchTables().listen((tables) {
      remoteTables = tables;
      final allowed = tables.map((t) => t.id).toSet();
      remotePosts.removeWhere((post) => !post.tableIds.any(allowed.contains));
      if (!tableId.startsWith('local-') && !allowed.contains(tableId)) {
        selectTable(localTables.first.id);
      }
      syncError = null;
      _watchSelectedTable();
      notifyListeners();
    }, onError: _syncFailed);
    _watchSelectedTable();
  }

  void _watchSelectedTable() {
    if (_watchedTable == tableId) return;
    unawaited(_postsSubscription?.cancel());
    _watchedTable = tableId;
    if (!cloud.signedIn || tableId.startsWith('local-')) return;
    final selected = tableId;
    _postsSubscription = cloud.watchPosts(selected).listen((posts) {
      if (selected != tableId) return;
      remotePosts.removeWhere((post) => post.tableIds.contains(selected));
      remotePosts.addAll(posts);
      syncError = null;
      notifyListeners();
    }, onError: _syncFailed);
  }

  void _syncFailed(Object error) {
    syncError = '새 기록을 불러오지 못했어요. 아래로 당겨 다시 확인해 주세요.';
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_tablesSubscription?.cancel());
    unawaited(_postsSubscription?.cancel());
    super.dispose();
  }
}
