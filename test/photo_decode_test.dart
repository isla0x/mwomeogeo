import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:mwomeogeo/cloud.dart';
import 'package:mwomeogeo/design.dart';
import 'package:mwomeogeo/models.dart';
import 'package:mwomeogeo/shared_photo.dart';
import 'package:mwomeogeo/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shared JPEG decodes from an offset byte view', () async {
    final bytes = encodeSharedPhoto(
      await File('assets/photos/bowl.jpg').readAsBytes(),
    );
    final buffer = Uint8List(bytes.length + 24)
      ..setRange(24, bytes.length + 24, bytes);
    final view = Uint8List.sublistView(buffer, 24);
    for (final value in [Blob(view), view, List<Object?>.from(view)]) {
      final photo = readSharedPhoto(value);
      expect(photo.offsetInBytes, 0);
      expect(photo, bytes);
      expect(identical(photo.buffer, view.buffer), false);
      final codec = await ui.instantiateImageCodec(photo);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0));
      frame.image.dispose();
      codec.dispose();
    }
    expect(() => readSharedPhoto(null), throwsA(isA<CloudFailure>()));
    expect(() => readSharedPhoto(Uint8List(0)), throwsA(isA<CloudFailure>()));
    for (final invalid in [
      [256],
      [-1],
      [1.5],
      ['1'],
    ]) {
      expect(() => readSharedPhoto(invalid), throwsA(isA<CloudFailure>()));
    }
  });

  testWidgets('failed cloud photo retries and displays returned bytes', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(() async {
      setupFirebaseCoreMocks();
      await Firebase.initializeApp();
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('photo-retry-');
      return (
        directory,
        MealStore(await SharedPreferences.getInstance(), directory),
        encodeSharedPhoto(await File('assets/photos/bowl.jpg').readAsBytes()),
      );
    }))!;
    final (directory, store, bytes) = fixture;
    addTearDown(() async {
      store.dispose();
      await directory.delete(recursive: true);
    });
    const path = 'tables/test/photos/test';
    final post = MealPost(
      id: 'test',
      author: '나',
      photo: 'cloud:$path',
      meal: 0,
      date: DateTime.now(),
      tableIds: ['test'],
    );
    const channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet',
      FirebaseFirestoreHostApi.codec,
    );
    var reads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<Object?>(channel, (_) async {
      reads++;
      if (reads == 1) return ['unavailable', 'offline', null];
      return [
        PigeonDocumentSnapshot(
          path: path,
          data: {'data': bytes},
          metadata: PigeonSnapshotMetadata(
            hasPendingWrites: false,
            isFromCache: false,
          ),
        ),
      ];
    });
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
    );
    Widget photo() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 260,
          child: MealPhoto(post, store, edition: false),
        ),
      ),
    );
    await tester.pumpWidget(photo());
    await tester.pumpAndSettle();
    expect(
      find.byType(PhotoFallback),
      findsOneWidget,
      reason:
          'reads=$reads; ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
    );
    expect(reads, 1);
    await tester.pumpWidget(photo());
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.tap(find.text('다시 불러오기'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(
      find.byType(PhotoFallback),
      findsNothing,
      reason:
          '${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, bytes);
  });
}
