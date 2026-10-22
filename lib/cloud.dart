import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'shared_photo.dart';

import 'firebase_options.dart';
import 'models.dart';

/// Anonymous Firebase identity is persisted by the native SDK. No login UI,
/// passwords, public download URLs, or service-account keys are needed.
class CloudApi {
  static bool _ready = false;
  static String? initializationError;
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

  Future<String> identityToken() => _guard(() async {
    if (!signedIn) throw const CloudFailure('식탁 연결을 먼저 확인해 주세요.');
    final token = await _auth.currentUser!.getIdToken();
    if (token == null) throw const CloudFailure('식탁 연결을 먼저 확인해 주세요.');
    return token;
  });

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
        'resource-exhausted' =>
          '무료 사용량 한도에 도달했어요. 잠시 후 다시 시도하거나 오래된 내 기록을 정리해 주세요.',
        _ => '식탁에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.',
      };
      throw CloudFailure(message);
    } on FormatException catch (e) {
      throw CloudFailure(e.message);
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
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 20) {
      throw const CloudFailure('식탁 이름은 1~20자로 입력해 주세요.');
    }
    final random = Random.secure();
    final code = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    final table = _db.collection('tables').doc();
    final batch = _db.batch();
    batch.set(table, {
      'name': trimmed,
      'ownerId': userId,
      'memberIds': [userId],
      'inviteCode': code,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('_invites').doc(code), {
      'tableId': table.id,
      'ownerId': userId,
    });
    await batch.commit();
    return table.id;
  });
  Future<String> joinTable(String code) => _guard(() async {
    final normalized = code.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{32}$').hasMatch(normalized)) {
      throw const CloudFailure('복사한 초대 코드 32자리를 입력해 주세요.');
    }
    final invite = await _db.collection('_invites').doc(normalized).get();
    if (!invite.exists) throw const CloudFailure('초대 코드를 다시 확인해 주세요.');
    final id = invite.data()!['tableId'] as String;
    // The rules verify the code and allow only this user's membership addition.
    await _db.collection('tables').doc(id).update({
      'memberIds': FieldValue.arrayUnion([userId]),
      'joinCode': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
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
  ) => Future.wait(snapshot.docs.map((doc) => _readPost(tableId, doc)));
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

  Future<Uint8List> photoBytes(String path, {bool refresh = false}) {
    if (refresh) {
      _photos.remove(path);
      _photoSizes.remove(path);
    }
    if (_photos.containsKey(path)) return _photos[path]!;
    // Bound the in-memory cache; private photos are never given public URLs.
    if (_photos.length >= 32) {
      final oldest = _photos.keys.first;
      _photos.remove(oldest);
      _photoSizes.remove(oldest);
    }
    final future = _guard(() async {
      final photo = await _db.doc(path).get();
      if (!photo.exists) {
        throw const CloudFailure('저장된 사진을 찾지 못했어요. 다시 불러와 주세요.');
      }
      return readSharedPhoto(photo.data()?['data']);
    });
    _photos[path] = future;
    future.then<void>(
      (bytes) {
        if (!identical(_photos[path], future)) return;
        _photoSizes[path] = bytes.length;
        while (_photoSizes.values.fold<int>(
                  0,
                  (totalBytes, size) => totalBytes + size,
                ) >
                24 * 1024 * 1024 &&
            _photos.length > 1) {
          final oldest = _photos.keys.first;
          _photos.remove(oldest);
          _photoSizes.remove(oldest);
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_photos[path], future)) {
          _photos.remove(path);
          _photoSizes.remove(path);
        }
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
    if (tableIds.isEmpty || tableIds.length > 5) {
      throw const CloudFailure('한 번에 식탁 1~5개를 선택해 주세요.');
    }
    final input = await file.readAsBytes();
    if (input.length > 10 * 1024 * 1024) {
      throw const CloudFailure('사진은 10MB 이하로 골라 주세요.');
    }
    final bytes = await compute(encodeSharedPhoto, input);
    final batch = _db.batch();
    final result = <MealPost>[];
    final now = DateTime.now();
    for (final tableId in tableIds) {
      final id = newId();
      final path = 'tables/$tableId/photos/$id';
      batch.set(_db.doc(path), {'authorId': userId, 'data': Blob(bytes)});
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
    final ref = _postCollection(post.tableIds.single).doc(post.id);
    // Freeze replies first. A failed cleanup can be retried; the post stays visible.
    await ref.update({
      'deleting': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final name in ['comments', 'reactions']) {
      while (true) {
        final children = await ref.collection(name).limit(100).get();
        if (children.docs.isEmpty) break;
        final batch = _db.batch();
        for (final child in children.docs) {
          batch.delete(child.reference);
        }
        await batch.commit();
      }
    }
    final batch = _db.batch();
    batch.delete(_db.doc(post.photo.substring(6)));
    batch.delete(ref);
    await batch.commit();
    _photos.remove(post.photo.substring(6));
  });
}

Uint8List readSharedPhoto(Object? value) {
  final bytes = switch (value) {
    Blob(:final bytes) => bytes,
    Uint8List bytes => bytes,
    List values
        when values.every(
          (value) => value is int && value >= 0 && value <= 255,
        ) =>
      values.cast<int>(),
    _ => throw const CloudFailure('사진 데이터 형식을 읽지 못했어요.'),
  };
  if (bytes.isEmpty) throw const CloudFailure('저장된 사진 데이터가 비어 있어요.');
  // Own the image buffer independently of the native Firestore message buffer.
  return Uint8List.fromList(bytes);
}

class CloudFailure implements Exception {
  const CloudFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
