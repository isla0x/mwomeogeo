import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/nudges.dart';

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  set contentType(ContentType? value) {}
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.body);
  @override
  final int statusCode;
  final Map<String, dynamic> body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(body))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.route, this.reply);
  final String route;
  final _Response Function(String, Map<String, dynamic>) reply;
  final _body = StringBuffer();
  @override
  final headers = _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  void write(Object? object) => _body.write(object);
  @override
  Future<HttpClientResponse> close() async =>
      reply(route, jsonDecode(_body.toString()) as Map<String, dynamic>);
}

class _Client extends Fake implements HttpClient {
  _Client(this.reply);
  final _Response Function(String, Map<String, dynamic>) reply;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request(url.path, reply);
  @override
  void close({bool force = false}) {}
}

class _Overrides extends HttpOverrides {
  _Overrides(this.reply);
  final _Response Function(String, Map<String, dynamic>) reply;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(reply);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late MealNudges nudges;
  late SharedPreferences prefs;
  late List<(String, Map<String, dynamic>)> calls;
  late bool fail;
  late bool permission;
  HttpOverrides? previous;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls = [];
    fail = false;
    permission = true;
    previous = HttpOverrides.current;
    HttpOverrides.global = _Overrides((route, body) {
      calls.add((route, body));
      return fail
          ? _Response(503, {'error': 'unavailable'})
          : _Response(200, {'accepted': 1, 'enabled': true});
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MealNudges.channel,
      (call) async => call.method == 'register' && permission
          ? {'token': 'a' * 64, 'environment': 'production'}
          : null,
    );
    nudges = MealNudges(prefs, () async => 'test-token');
  });
  tearDown(() {
    nudges.dispose();
    HttpOverrides.global = previous;
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MealNudges.channel,
      null,
    );
  });

  test(
    'new categories default off without changing legacy nudge consent',
    () async {
      expect(nudges.notificationPreferences, {
        'nudge': false,
        'post': false,
        'comment': false,
        'like': false,
      });
      await prefs.setBool('mealNudges', true);
      expect(nudges.enabled, isTrue);
      expect(nudges.postsEnabled, isFalse);
      expect(nudges.commentsEnabled, isFalse);
    },
  );

  test(
    'categories update independently; last off disables the device',
    () async {
      await nudges.setPreference('table', 'post', true);
      await nudges.setPreference('table', 'comment', true);
      await nudges.setPreference('table', 'post', false);
      expect(calls.last.$1, '/devices');
      expect(calls.last.$2['preferences'], {
        'nudge': false,
        'post': false,
        'comment': true,
        'like': false,
      });
      expect(nudges.commentsEnabled, isTrue);
      await nudges.setPreference('table', 'comment', false);
      expect(calls.last.$1, '/disable');
      expect(nudges.anyEnabled, isFalse);
    },
  );

  test(
    'denied permission and server failure do not save an enabled toggle',
    () async {
      permission = false;
      await expectLater(
        nudges.setPreference('table', 'post', true),
        throwsException,
      );
      expect(nudges.postsEnabled, isFalse);
      permission = true;
      fail = true;
      await expectLater(
        nudges.setPreference('table', 'comment', true),
        throwsException,
      );
      expect(nudges.commentsEnabled, isFalse);
      expect(nudges.busy, isFalse);
    },
  );

  test(
    'failed event delivery is retained then drained on the next restore',
    () async {
      fail = true;
      await nudges.activity('table', 'post', commentId: 'comment');
      await pumpEventQueue();
      expect(prefs.getStringList('activityOutbox'), hasLength(1));
      fail = false;
      await nudges.restore('table');
      await pumpEventQueue();
      expect(prefs.getStringList('activityOutbox'), isEmpty);
      expect(calls.last.$1, '/activity');
      expect(calls.last.$2, {
        'tableId': 'table',
        'postId': 'post',
        'kind': 'comment',
        'commentId': 'comment',
      });
    },
  );

  test(
    'like consent is independent and reaction identity reaches the server',
    () async {
      await nudges.setPreference('table', 'like', true);
      expect(nudges.likesEnabled, isTrue);
      expect(nudges.postsEnabled, isFalse);
      expect(calls.last.$2['preferences']['like'], isTrue);
      await nudges.activity('table', 'post', reactionId: 'user_heart');
      await pumpEventQueue();
      expect(calls.last.$1, '/activity');
      expect(calls.last.$2['kind'], 'like');
      expect(calls.last.$2['reactionId'], 'user_heart');
    },
  );

  test('stale events expire without requesting a historical push', () async {
    await prefs.setStringList('activityOutbox', [
      jsonEncode({
        'tableId': 'table',
        'postId': 'post',
        'kind': 'post',
        'queuedAt': DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
      }),
    ]);
    await nudges.flushActivities();
    expect(calls, isEmpty);
    expect(prefs.getStringList('activityOutbox'), isEmpty);
  });
}
