import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/main.dart';
import 'package:mwomeogeo/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MealStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('mwomeogeo-ui-');
    store = MealStore(await SharedPreferences.getInstance(), directory);
    await store.load();
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf'));
    await font.load();
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });
  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/previews').create(recursive: true);
    await File('build/previews/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  }

  testWidgets(
    'reference feed, calendar and empty state render at native iPhone size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MwomeogeoApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('오늘도 잘 먹고 있어?'), findsOneWidget);
      expect(find.text('지우'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '01-feed');
      await tester.tap(find.text('모아보기'));
      await tester.pumpAndSettle();
      expect(find.text('우리의 하루.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '02-calendar');
      await tester.tap(find.text('우리 식탁'));
      await store.setDemo(false);
      await tester.pumpAndSettle();
      expect(find.text('점심 식탁은\n아직 비어 있어요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '03-empty');
      await tester.tap(find.text('한 끼 남기기'));
      await tester.pumpAndSettle();
      expect(find.text('사진첩에는 저장하지 않아요'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '04-camera');
    },
  );
  testWidgets('small display and large text retain usable navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MwomeogeoApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('한 끼 남기기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
