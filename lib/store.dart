import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'models.dart';
import 'nudges.dart';

class MealStore extends ChangeNotifier {
  MealStore(this.preferences, this.directory);
  final SharedPreferences preferences;
  final Directory directory;
  final CloudApi cloud = CloudApi();
  late final nudges = MealNudges(preferences, cloud.identityToken);
  StreamSubscription<List<DiningTable>>? _tablesSubscription;
  StreamSubscription<List<MealPost>>? _postsSubscription;
  String? _watchedTable;
  String? syncError;
  Future<void>? _connectionAttempt;
  final List<MealPost> previewPosts = demoPosts(DateTime.now());
  List<MealPost> localPosts = [];
  List<MealPost> remotePosts = [];
  List<DiningTable> remoteTables = [];
  bool demo = false;
  String name = '나';
  String tableId = '';
  List<DiningTable> localTables = [];
  static const previewTables = [
    DiningTable('local-couple', '우리 둘'),
    DiningTable('local-family', '가족 식탁'),
  ];
  List<DiningTable> get tables =>
      demo ? previewTables : [...localTables, ...remoteTables];
  DiningTable? get table {
    for (final candidate in tables) {
      if (candidate.id == tableId) return candidate;
    }
    return tables.isEmpty ? null : tables.first;
  }

  List<MealPost> get allPosts =>
      demo ? previewPosts : [...localPosts, ...remotePosts];
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
    // Preview is opt-in for this session, including after upgrading old installs.
    demo = false;
    name = preferences.getString('name') ?? '나';
    tableId = preferences.getString('selectedTable') ?? '';
    final savedTables = preferences.getString('localTables');
    if (savedTables != null) {
      localTables = (jsonDecode(savedTables) as List)
          .map(
            (item) => DiningTable(item['id'] as String, item['name'] as String),
          )
          .toList();
    }
    final raw = preferences.getString('posts');
    if (raw != null) {
      localPosts = (jsonDecode(raw) as List)
          .map((j) => MealPost.fromJson(j))
          .toList();
    }
    final recordedIds = localPosts.expand((post) => post.tableIds).toSet();
    for (final legacy in previewTables) {
      if (recordedIds.contains(legacy.id) &&
          !localTables.any((table) => table.id == legacy.id)) {
        localTables.add(legacy);
      }
    }
    _reconcileSelection();
  }

  Future<void> createLocalTable(String value) async {
    final name = value.trim();
    if (name.isEmpty || name.length > 20) {
      throw ArgumentError('식탁 이름을 1~20자로 적어 주세요.');
    }
    final table = DiningTable('local-${newId()}', name);
    final updated = [...localTables, table];
    final ok = await preferences.setString(
      'localTables',
      jsonEncode([
        for (final table in updated) {'id': table.id, 'name': table.name},
      ]),
    );
    if (!ok) throw const FileSystemException('식탁을 저장하지 못했어요.');
    localTables = updated;
    demo = false;
    selectTable(table.id);
  }

  void _reconcileSelection() {
    if (!tables.any((table) => table.id == tableId)) {
      final savedId = preferences.getString('selectedTable');
      tableId = tables.isEmpty ? '' : tables.first.id;
      if (tables.any((table) => table.id == savedId)) tableId = savedId!;
    }
    _watchSelectedTable();
  }

  Future<void> _save() async {
    final ok = await preferences.setString(
      'posts',
      jsonEncode(localPosts.map((p) => p.toJson()).toList()),
    );
    if (!ok) throw const FileSystemException('기록을 저장하지 못했어요. 저장 공간을 확인해 주세요.');
  }

  Future<void> setDemo(bool value) async {
    demo = value;
    tableId = value
        ? previewTables.first.id
        : preferences.getString('selectedTable') ?? '';
    _reconcileSelection();
    notifyListeners();
  }

  Future<void> setName(String value) async {
    await cloud.setDisplayName(value.trim());
    await preferences.setString('name', value.trim());
    name = value.trim();
    notifyListeners();
  }

  void selectTable(String id) {
    if (!tables.any((table) => table.id == id)) return;
    tableId = id;
    if (!demo) unawaited(preferences.setString('selectedTable', id));
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
    _reconcileSelection();
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
    if (demo ||
        tableIds.isEmpty ||
        tableIds.any((id) => !tables.any((table) => table.id == id))) {
      throw ArgumentError('먼저 식탁을 만들거나 초대 코드로 참여해 주세요.');
    }
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
    await _tablesSubscription?.cancel();
    _tablesSubscription = cloud.watchTables().listen((tables) {
      remoteTables = tables;
      final allowed = tables.map((t) => t.id).toSet();
      remotePosts.removeWhere((post) => !post.tableIds.any(allowed.contains));
      _reconcileSelection();
      syncError = null;
      _watchSelectedTable();
      notifyListeners();
    }, onError: _syncFailed);
    _watchSelectedTable();
    await nudges.restore(tableId);
  }

  void _watchSelectedTable() {
    if (_watchedTable == tableId) return;
    unawaited(_postsSubscription?.cancel());
    _watchedTable = tableId;
    if (demo ||
        tableId.isEmpty ||
        !cloud.signedIn ||
        tableId.startsWith('local-')) {
      return;
    }
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
    nudges.dispose();
    super.dispose();
  }
}
