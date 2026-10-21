import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'models.dart';

// Public HTTPS address only. Apple signing keys stay in the server's secrets.
const nudgeApiUrl = String.fromEnvironment('NUDGE_API_URL');

class MealNudges extends ChangeNotifier {
  MealNudges(this.preferences, this.idToken, {Uri? endpoint})
    : endpoint = endpoint ?? Uri.tryParse(nudgeApiUrl);
  final SharedPreferences preferences;
  final Future<String> Function() idToken;
  final Uri? endpoint;
  static const channel = MethodChannel('com.chaen.mwomeogeo/nudges');
  bool get configured =>
      endpoint != null &&
      endpoint!.scheme == 'https' &&
      endpoint!.host.isNotEmpty;
  bool get enabled => preferences.getBool('mealNudges') ?? false;
  bool busy = false;
  void Function(String)? onOpen;

  Future<Map<String, dynamic>> _request(
    String route,
    Map<String, dynamic> body,
  ) async {
    if (!configured) throw const CloudFailure('식사 알림을 준비 중이에요. 다음 업데이트에서 만나요.');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(endpoint!.resolve(route));
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${await idToken()}',
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw CloudFailure(switch (data['error']) {
          'cooldown' => '같은 식사 알림은 30분에 한 번 보낼 수 있어요.',
          'no_devices' => '아직 알림을 받을 사람이 없어요. 상대가 식사 알림 받기를 켜야 해요.',
          'unauthorized' || 'forbidden' => '식탁 연결을 확인하고 다시 시도해 주세요.',
          'delivery_failed' => '알림 전송을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
          'pending' => '앞서 보낸 알림을 처리 중이에요. 잠시만 기다려 주세요.',
          _ => '알림을 보내지 못했어요. 잠시 후 다시 시도해 주세요.',
        });
      }
      return data;
    } on CloudFailure {
      rethrow;
    } catch (_) {
      throw const CloudFailure('알림 연결을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> setEnabled(String tableId, bool value) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      if (value) {
        await _register(tableId, ask: true);
      } else {
        await _request('/disable', {'tableId': tableId});
      }
      await preferences.setBool('mealNudges', value);
    } on PlatformException {
      throw const CloudFailure('알림을 허용하지 않았어요. iPhone 설정에서 알림을 허용해 주세요.');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _register(String tableId, {required bool ask}) async {
    if (!configured) throw const CloudFailure('식사 알림을 준비 중이에요. 다음 업데이트에서 만나요.');
    if (!Platform.isIOS) {
      throw const CloudFailure('지금은 iPhone에서 식사 알림을 받을 수 있어요.');
    }
    final device = await channel
        .invokeMapMethod<String, dynamic>('register', {'ask': ask})
        .timeout(const Duration(seconds: 30));
    if (device == null) {
      if (!ask) {
        await _request('/disable', {'tableId': tableId});
        await preferences.setBool('mealNudges', false);
        notifyListeners();
        return;
      }
      throw const CloudFailure('알림을 허용하지 않았어요. iPhone 설정에서 알림을 허용해 주세요.');
    }
    await _request('/devices', {'tableId': tableId, ...device});
  }

  // Refresh APNs tokens after launch/resume, without prompting for permission.
  Future<void> restore(String? tableId) async {
    if (!configured ||
        !Platform.isIOS ||
        tableId == null ||
        tableId.startsWith('local-')) {
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'opened' && call.arguments is Map) {
        final id = (call.arguments as Map)['tableId'];
        if (id is String) onOpen?.call(id);
      }
    });
    final opened = await channel.invokeMapMethod<String, dynamic>('takeOpen');
    if (opened?['tableId'] case final String id) {
      onOpen?.call(id);
    }
    if (enabled && !busy) {
      try {
        await _register(tableId, ask: false);
      } catch (_) {
        /* Retry next resume; never interrupt a meal. */
      }
    }
  }

  Future<int> send(
    String tableId,
    int meal, {
    required String requestId,
  }) async {
    if (meal < 0 || meal > 2) throw ArgumentError.value(meal, 'meal');
    final result = await _request('/nudge', {
      'tableId': tableId,
      'meal': meal,
      'requestId': requestId,
    });
    final accepted = result['accepted'];
    if (accepted is! int || accepted < 1) {
      throw const CloudFailure('알림 전송 결과를 확인하지 못했어요.');
    }
    return accepted;
  }
}

String mealNudgeText(int meal) => '${mealNames[meal]} 뭐 먹어!?';
