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
import 'package:mwomeogeo/models.dart';
import 'package:mwomeogeo/post_card.dart';

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
    for (final entry in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
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
    await tester.runAsync(() async {
      await Future.wait([
        for (final name in ['toast', 'bowl', 'pasta', 'salad'])
          precacheImage(
            AssetImage('assets/photos/$name.jpg'),
            key.currentContext!,
          ),
        precacheImage(
          const AssetImage('assets/illustrations/first-table.png'),
          key.currentContext!,
        ),
      ]);
    });
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
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.setDemo(false);
    final firstKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: firstKey,
        child: MwomeogeoApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await screenshot(tester, firstKey, '06-first-room');
    expect(find.text('우리의 첫 식탁을\n만들어요'), findsOneWidget);
    expect(find.text('우리 둘'), findsNothing);
    expect(find.text('가족 식탁'), findsNothing);
    await tester.tap(find.text('첫 식탁 만들기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '새 식탁 이름'), '첫 식탁');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.textContaining('이 기기에 보관할 식탁을 만들어요.'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('첫 식탁'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextField, '새 식탁 이름'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
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
    await tester.ensureVisible(find.bySemanticsLabel('저녁 남기기'));
    await tester.tap(find.bySemanticsLabel('저녁 남기기'));
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
      expect(find.text('오늘도, 잘 먹었어?'), findsOneWidget);
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
      expect(find.bySemanticsLabel('저녁 남기기'), findsOneWidget);
      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();
      expect(find.text('우리의 하루.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '02-calendar');
      await tester.tap(find.text('식탁'));
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
      await tester.tap(find.text('남기기'));
      await tester.pumpAndSettle();
      expect(find.text('사진첩에는 저장하지 않아요'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '04-camera');
    },
  );
  testWidgets(
    'same meal uses two columns, odd rows and narrow-screen fallback',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await store.setDemo(false);
      await store.createLocalTable('우리 식탁');
      for (var i = 0; i < 3; i++) {
        store.localPosts.add(
          MealPost(
            id: 'pair-$i',
            author: ['지우', '채은', '엄마'][i],
            authorId: 'local',
            photo: 'asset:${i == 1 ? 'bowl' : 'toast'}',
            meal: 0,
            date: DateTime.now(),
            tableIds: [store.tableId],
            caption: '아침도 든든하게 $i',
          ),
        );
      }
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MwomeogeoApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      final ordered = store.postsOn(DateTime.now());
      final first = find.byKey(ValueKey('post-${ordered[0].id}'));
      final second = find.byKey(ValueKey('post-${ordered[1].id}'));
      final third = find.byKey(ValueKey('post-${ordered[2].id}'));
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(
        tester.getTopLeft(second).dx,
        greaterThan(tester.getTopLeft(first).dx),
      );
      expect(
        tester.getTopLeft(third).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      expect(tester.widget<PostCard>(first).tile, isTrue);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, '07-paired-meals');
      await tester.tap(find.bySemanticsLabel('아침 사진 크게 보기').first);
      await tester.pumpAndSettle();
      expect(find.text('아침의 기록'), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.widget<PostCard>(first).tile, isFalse);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      expect(tester.widget<PostCard>(first).tile, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compose preserves caption, photo and recipient when dismissing keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await store.setDemo(false);
      await store.createLocalTable('우리 식탁');
      final source = File('${directory.path}/picked.jpg');
      await tester.runAsync(() async {
        await source.writeAsBytes(
          (await rootBundle.load('assets/photos/bowl.jpg')).buffer
              .asUint8List(),
        );
      });
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        (_) async => source.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MwomeogeoApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('남기기'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(FileImage(source), key.currentContext!),
      );
      await tester.tap(find.text('기존 사진 고르기'));
      await tester.pumpAndSettle();
      expect(find.text('사진 바꾸기'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '바쁜 날에도 든든하게 한 그릇.');
      await tester.pump();
      await tester.tap(find.text('오늘의 한마디'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('바쁜 날에도 든든하게 한 그릇.'), findsOneWidget);
      expect(find.text('우리 식탁'), findsOneWidget);
      await screenshot(tester, key, '08-compose');
      await tester.tap(find.text('사진 바꾸기'));
      await tester.pumpAndSettle();
      await screenshot(tester, key, '11-photo-options');
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(find.text('바쁜 날에도 든든하게 한 그릇.'), findsOneWidget);

      await tester.ensureVisible(find.text('식탁에 남기기'));
      await tester.runAsync(() async {
        await tester.tap(find.text('식탁에 남기기'));
        for (var i = 0; i < 100 && store.localPosts.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(store.localPosts.single.caption, '바쁜 날에도 든든하게 한 그릇.');
      expect(find.text('안부로 놓아두었어요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('record actions cancel safely and deletion needs confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.setDemo(false);
    await store.setName('채은');
    await store.createLocalTable('우리 둘');
    final post = MealPost(
      id: 'menu-record',
      author: '채은',
      authorId: 'local',
      photo: 'asset:bowl',
      meal: 0,
      date: DateTime.now(),
      tableIds: [store.tableId],
      caption: '바쁜 날에도 든든하게 한 그릇.',
    );
    store.localPosts.add(post);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MwomeogeoApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기록 메뉴').first);
    await tester.pumpAndSettle();
    expect(find.text('사진과 한마디 공유'), findsOneWidget);
    await screenshot(tester, key, '09-record-menu');
    await tester.tap(find.text('기록 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('이 기록을 삭제할까요?'), findsOneWidget);
    await screenshot(tester, key, '10-delete-dialog');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(store.localPosts, hasLength(1));
    await tester.tap(find.byTooltip('기록 메뉴').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 삭제'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('삭제'));
      for (var i = 0; i < 100 && store.localPosts.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Finish local persistence and the notifyListeners callback.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(store.localPosts, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('name sheet rejects blank names and fits a visible keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await store.setName('채은');
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MwomeogeoApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('내 정보와 식탁 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이름 변경'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).last, '채은');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await screenshot(tester, key, '12-name-sheet');
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).last, '윤채은');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(store.name, '윤채은');
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });
  testWidgets('small display and large text retain usable navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MwomeogeoApp(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await screenshot(tester, key, '05-small-text');
    await tester.tap(find.text('남기기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
