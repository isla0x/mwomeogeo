import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwomeogeo/camera_header.dart';

class FakeMealCamera extends CameraPlatform {
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final orientations =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  final created = <CameraDescription>[];
  final audio = <bool>[];
  final disposed = <int>[];
  bool denied = false;
  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    if (denied) throw PlatformException(code: 'CameraAccessDenied');
    created.add(description);
    audio.add(enableAudio);
    return created.length;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) => Stream.value(
    CameraInitializedEvent(
      id,
      1280,
      720,
      ExposureMode.auto,
      true,
      FocusMode.auto,
      true,
    ),
  );
  @override
  Stream<CameraErrorEvent> onCameraError(int id) =>
      errors.stream.where((event) => event.cameraId == id);
  @override
  Future<void> initializeCamera(
    int id, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Future<void> lockCaptureOrientation(
    int id,
    DeviceOrientation orientation,
  ) async {}
  @override
  Widget buildPreview(int id) =>
      ColoredBox(key: ValueKey('preview-$id'), color: Colors.brown);
  @override
  Future<XFile> takePicture(int id) async => XFile('/tmp/meal-camera-test.jpg');
  @override
  Future<void> dispose(int id) async {
    disposed.add(id);
    errors.add(CameraErrorEvent(id, 'Disposed'));
  }
}

void cameraTest(String description, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      description,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

void main() {
  cameraTest(
    'live camera captures without audio, flips and releases on background and covered routes',
    (tester) async {
      final original = CameraPlatform.instance;
      final fake = FakeMealCamera();
      CameraPlatform.instance = fake;
      addTearDown(() {
        CameraPlatform.instance = original;
      });
      final navigator = GlobalKey<NavigatorState>();
      String? captured;
      var galleries = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [mealCameraRoutes],
          home: Scaffold(
            body: MealCameraHeader(
              header: const SizedBox(),
              onPhoto: (file) async => captured = file.path,
              onCamera: () {},
              onGallery: () => galleries++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.created.single.lensDirection, CameraLensDirection.back);
      expect(fake.audio, everyElement(isFalse));
      await tester.tap(find.byTooltip('기존 사진 고르기'));
      expect(galleries, 1);
      await tester.tap(find.byTooltip('카메라 전환'));
      await tester.pumpAndSettle();
      expect(fake.created.last.lensDirection, CameraLensDirection.front);
      expect(fake.disposed, contains(1));
      await tester.tap(find.bySemanticsLabel('식사 사진 촬영'));
      await tester.pumpAndSettle();
      expect(captured, '/tmp/meal-camera-test.jpg');
      expect(fake.created.length, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(fake.disposed, contains(3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fake.created.length, 4);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('작성 화면')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.disposed, contains(4));
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fake.created.length, 5);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(fake.disposed.toSet().length, fake.created.length);
      await fake.errors.close();
      await fake.orientations.close();
      expect(tester.takeException(), isNull);
    },
  );

  cameraTest(
    'permission denial retains gallery and native-camera fallback without a fake live photo',
    (tester) async {
      final original = CameraPlatform.instance;
      final fake = FakeMealCamera()..denied = true;
      CameraPlatform.instance = fake;
      addTearDown(() {
        CameraPlatform.instance = original;
      });
      var native = 0;
      var gallery = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [mealCameraRoutes],
          home: Scaffold(
            body: MealCameraHeader(
              header: const SizedBox(),
              onPhoto: (_) async {},
              onCamera: () => native++,
              onGallery: () => gallery++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('카메라 권한'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.byTooltip('기존 사진 고르기'));
      await tester.tap(find.bySemanticsLabel('식사 사진 촬영'));
      expect(gallery, 1);
      expect(native, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await fake.errors.close();
      await fake.orientations.close();
      expect(tester.takeException(), isNull);
    },
  );
}
