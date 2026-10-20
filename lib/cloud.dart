import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_options.dart';
import 'models.dart';

/// Anonymous Firebase identity is persisted by the native SDK. No login UI,
/// passwords, public download URLs, or service-account keys are needed.
class CloudApi {
  static bool _ready = false;
  static String? initializationError;
  static const functionsRegion = 'asia-northeast3';
  static Future<void> initialize() async {
    FirebaseOptions options;
    try {
      options = DefaultFirebaseOptions.currentPlatform;
    } on UnsupportedError {
      return;
    }
    try {
      await Firebase.initializeApp(options: options);
      _ready = true;
    } catch (_) {
      initializationError = '식탁 연결을 준비하지 못했어요. 잠시 후 다시 시도해 주세요.';
    }
  }

  bool get configured => _ready;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: functionsRegion);
  bool get signedIn => configured && _auth.currentUser != null;
  String? get userId => signedIn ? _auth.currentUser!.uid : null;
  String? get displayName => signedIn ? _auth.currentUser!.displayName : null;
  final Map<String, Future<Uint8List>> _photos = {};
  final Map<String, int> _photoSizes = {};
  Future<void>? _identityAttempt;

  Future<void> ensureIdentity(String name) =>
      _identityAttempt ??= _ensureIdentity(name)
          .whenComplete(() => _identityAttempt = null);

  Future<void> _ensureIdentity(String name) async {
    if (!configured) {
      throw const CloudFailure('공유 식탁 연결 전이에요. 이 기기에 먼저 기록할 수 있어요.');
    }
    await _guard(() async {
      final restored = await _auth.authStateChanges().first;
      if (restored == null) {
        await _auth.signInAnonymously().timeout(const Duration(seconds: 25));
      }
      if ((_auth.currentUser!.displayName ?? '').isEmpty) {
        await _auth.currentUser!.updateDisplayName(name);
      }
    });
  }

  Future<void> setDisplayName(String name) async {
    if (signedIn) {
      await _guard(() => _auth.currentUser!.updateDisplayName(name));
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      final message = switch (e.code) {
        'operation-not-allowed' => '익명 인증이 아직 연결되지 않았어요.',
        'network-request-failed' ||
        'unavailable' ||
        'deadline-exceeded' => '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
        'permission-denied' ||
        'unauthorized' => '이 식탁을 볼 권한이 없어요. 초대 코드와 연결 설정을 확인해 주세요.',
        'not-found' => '식탁 연결 설정을 확인해 주세요.',
        'invalid-argument' => e.message ?? '입력한 내용을 확인해 주세요.',
        'resource-exhausted' => '지금은 요청이 많아요. 잠시 후 다시 시도해 주세요.',
        _ => '식탁에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
      throw CloudFailure(message);
    } on CloudFailure {
      rethrow;
    } catch (_) {
      throw const CloudFailure('연결을 완료하지 못했어요. 사진은 그대로 두었으니 다시 시도해 주세요.');
    }
  }

  Query<Map<String, dynamic>> get _tablesQuery =>
      _db.collection('tables').where('memberIds', arrayContains: userId);
  List<DiningTable> _readTables(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs.map((doc) {
        final d = doc.data();
        return DiningTable(
          doc.id,
          d['name'] as String,
          memberCount: (d['memberIds'] as List).length,
          inviteCode: d['inviteCode'] as String,
        );
      }).toList()..sort((a, b) => a.name.compareTo(b.name));
  Future<List<DiningTable>> tables() =>
      _guard(() async => _readTables(await _tablesQuery.get()));
  Stream<List<DiningTable>> watchTables() =>
      _tablesQuery.snapshots().map(_readTables);
  Future<String> createTable(String name) => _guard(() async {
    final result = await _functions.httpsCallable('createDiningTable').call({
      'name': name.trim(),
    });
    return result.data['tableId'] as String;
  });
  Future<String> joinTable(String code) => _guard(() async {
    final result = await _functions.httpsCallable('joinDiningTable').call({
      'code': code.trim().toUpperCase(),
    });
    return result.data['tableId'] as String;
  });
  CollectionReference<Map<String, dynamic>> _postCollection(String tableId) =>
      _db.collection('tables').doc(tableId).collection('posts');
  Future<MealPost> _readPost(
    String tableId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final d = doc.data();
    final reactions = await doc.reference.collection('reactions').get();
    final comments = await doc.reference
        .collection('comments')
        .orderBy('createdAt')
        .get();
    return MealPost(
      id: doc.id,
      author: d['authorName'] as String,
      authorId: d['authorId'] as String,
      photo: 'cloud:${d['photoPath']}',
      meal: (d['meal'] as num).toInt(),
      date: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      tableIds: [tableId],
      caption: d['caption'] as String,
      reactions: reactions.docs
          .map((r) => '${r.data()['userId']}:${r.data()['kind']}')
          .toSet(),
      comments: comments.docs
          .map(
            (c) => MealComment(
              c.data()['authorName'] as String,
              c.data()['body'] as String,
            ),
          )
          .toList(),
    );
  }

  Future<List<MealPost>> _readPosts(
    String tableId,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => Future.wait(
    snapshot.docs
        .where((doc) => doc.data()['deleting'] != true)
        .map((doc) => _readPost(tableId, doc)),
  );
  Future<List<MealPost>> posts(String tableId) => _guard(
    () async => _readPosts(
      tableId,
      await _postCollection(tableId)
          .orderBy('createdAt', descending: true)
          .get(),
    ),
  );
  Stream<List<MealPost>> watchPosts(String tableId) =>
      _postCollection(tableId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .asyncMap((snapshot) => _readPosts(tableId, snapshot));

  Future<Uint8List> photoBytes(String path) {
    if (_photos.containsKey(path)) return _photos[path]!;
    // Bound the in-memory cache; private photos are never given public URLs.
    if (_photos.length >= 32) {
      final oldest = _photos.keys.first;
      _photos.remove(oldest);
      _photoSizes.remove(oldest);
    }
    final future = _guard(() async {
      final bytes = await _storage.ref(path).getData(10 * 1024 * 1024);
      if (bytes == null) throw const CloudFailure('사진을 불러오지 못했어요.');
      return bytes;
    });
    _photos[path] = future;
    future.then<void>(
      (bytes) {
        _photoSizes[path] = bytes.length;
        while (_photoSizes.values.fold<int>(0, (totalBytes, size) => totalBytes + size) >
                24 * 1024 * 1024 &&
            _photos.length > 1) {
          final oldest = _photos.keys.first;
          _photos.remove(oldest);
          _photoSizes.remove(oldest);
        }
      },
      onError: (Object _, StackTrace _) {
        _photos.remove(path);
      },
    );
    return future;
  }

  Future<List<MealPost>> sendMeal(
    File file,
    int meal,
    String caption,
    List<String> tableIds,
    String author,
  ) => _guard(() async {
    final bytes = await file.readAsBytes();
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    final jpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
    if (!png && !jpeg) throw const CloudFailure('JPEG 또는 PNG 사진을 골라 주세요.');
    if (bytes.length > 10 * 1024 * 1024) {
      throw const CloudFailure('사진은 10MB 이하로 골라 주세요.');
    }
    final extension = png ? 'png' : 'jpg';
    final metadata = SettableMetadata(
      contentType: png ? 'image/png' : 'image/jpeg',
      customMetadata: {'authorId': userId!},
    );
    final batch = _db.batch();
    final result = <MealPost>[];
    final now = DateTime.now();
    for (final tableId in tableIds) {
      final id = newId();
      final path = 'tables/$tableId/photos/$id/image.$extension';
      await _storage.ref(path).putData(bytes, metadata);
      batch.set(_postCollection(tableId).doc(id), {
        'authorId': userId,
        'authorName': author,
        'photoPath': path,
        'meal': meal,
        'caption': caption,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      result.add(
        MealPost(
          id: id,
          author: author,
          authorId: userId,
          photo: 'cloud:$path',
          meal: meal,
          date: now,
          tableIds: [tableId],
          caption: caption,
        ),
      );
    }
    await batch.commit();
    return result;
  });
  Future<void> react(MealPost post, String kind) => _guard(() async {
    final ref = _postCollection(post.tableIds.single).doc(post.id);
    final reaction = ref.collection('reactions').doc('${userId}_$kind');
    final batch = _db.batch();
    if (post.reactions.contains('$userId:$kind')) {
      batch.delete(reaction);
    } else {
      batch.set(reaction, {'userId': userId, 'kind': kind});
    }
    batch.update(ref, {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  });
  Future<void> comment(MealPost post, String body) => _guard(() async {
    final ref = _postCollection(post.tableIds.single).doc(post.id);
    final batch = _db.batch();
    batch.set(ref.collection('comments').doc(), {
      'authorId': userId,
      'authorName': displayName ?? '나',
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  });
  Future<void> deletePost(MealPost post) => _guard(() async {
    await _functions.httpsCallable('deleteMealPost').call({
      'tableId': post.tableIds.single,
      'postId': post.id,
    });
    _photos.remove(post.photo.substring(6));
  });
}

class CloudFailure implements Exception {
  const CloudFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
