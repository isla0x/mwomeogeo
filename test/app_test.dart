import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mwomeogeo/main.dart';
import 'package:mwomeogeo/compose.dart';
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
    await store.setDemo(true);
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
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/previews').create(recursive: true);
      await File('build/previews/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('new users create their own first room before writing', (
    tester,
  ) async {
    await store.setDemo(false);
    await tester.pumpWidget(MwomeogeoApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('아직 함께하는 식탁이 없어요.'), findsOneWidget);
    expect(find.text('우리 둘'), findsNothing);
    expect(find.text('가족 식탁'), findsNothing);
    await tester.tap(find.text('식탁 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '새 식탁 이름'), '첫 식탁');
    await tester.ensureVisible(find.text('식탁 만들기').last);
    await tester.tap(find.text('식탁 만들기').last);
    await tester.pumpAndSettle();
    expect(store.tables.single.name, '첫 식탁');
    expect(find.text('첫 식탁'), findsOneWidget);
    for (final meal in ['아침', '점심', '저녁']) {
      await tester.scrollUntilVisible(
        find.text('아직 남긴 $meal 사진이 없어요.'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('아직 남긴 $meal 사진이 없어요.'), findsOneWidget);
    }
    await tester.ensureVisible(find.text('저녁 남기기'));
    await tester.tap(find.text('저녁 남기기'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CaptureScreen>(find.byType(CaptureScreen)).initialMeal,
      2,
    );
    expect(tester.takeException(), isNull);
  });
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
      expect(find.text('지우'), findsWidgets);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '01-feed');
      await tester.scrollUntilVisible(
        find.text('오늘은 조금 가볍게. 너도 잘 챙겨 먹어.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('아직 남긴 저녁 사진이 없어요.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('저녁 남기기'), findsOneWidget);
      await tester.tap(find.text('모아보기'));
      await tester.pumpAndSettle();
      expect(find.text('우리의 하루.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '02-calendar');
      await tester.tap(find.text('우리 식탁'));
      await store.setDemo(false);
      await store.createLocalTable('우리 식탁');
      await tester.pumpAndSettle();
      for (final meal in ['아침', '점심', '저녁']) {
        await tester.scrollUntilVisible(
          find.text('아직 남긴 $meal 사진이 없어요.'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('아직 남긴 $meal 사진이 없어요.'), findsOneWidget);
      }
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
        data: const MediaQueryData(
          size: Size(320, 568),
          devicePixelRatio: 1,
          textScaler: TextScaler.linear(1.3),
        ),
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
