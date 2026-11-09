import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

final mealCameraRoutes = RouteObserver<ModalRoute<dynamic>>();

class MealCameraHeader extends StatefulWidget {
  const MealCameraHeader({
    super.key,
    required this.header,
    required this.onPhoto,
    required this.onCamera,
    required this.onGallery,
    this.demo = false,
    this.active = true,
  });
  final Widget header;
  final Future<void> Function(File) onPhoto;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final bool demo;
  final bool active;
  @override
  State<MealCameraHeader> createState() => MealCameraHeaderState();
}

class MealCameraHeaderState extends State<MealCameraHeader>
    with WidgetsBindingObserver, RouteAware {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  Future<void> _work = Future<void>.value();
  int _generation = 0;
  int _lens = 0;
  bool _shooting = false;
  String? _error;
  bool _loading = false;

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(resume());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) mealCameraRoutes.subscribe(this, route);
  }

  @override
  void didPushNext() => unawaited(pause());

  @override
  void didPopNext() {
    if (widget.active) unawaited(resume());
  }

  @override
  void didUpdateWidget(MealCameraHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.demo != widget.demo) {
      unawaited(widget.active ? resume() : pause());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(resume());
    } else if (state != AppLifecycleState.resumed) {
      unawaited(pause());
    }
  }

  // Serializing native camera operations prevents init/dispose races during
  // permission prompts, navigation, lens switching and application suspension.
  Future<void> _enqueue(Future<void> Function() action) {
    _work = _work.then((_) => action()).catchError((Object _) {});
    return _work;
  }

  Future<void> pause() {
    _generation++;
    return _enqueue(() async {
      final old = _controller;
      _controller = null;
      if (mounted) setState(() => _loading = false);
      await old?.dispose();
    });
  }

  Future<void> resume() {
    final generation = ++_generation;
    return _enqueue(() async {
      if (!mounted ||
          !widget.active ||
          widget.demo ||
          !_supported ||
          generation != _generation) {
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      if (_controller?.value.isInitialized == true) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      CameraController? next;
      try {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) throw CameraException('NoCamera', '');
        if (!mounted || generation != _generation) return;
        if (_lens >= _cameras.length) _lens = 0;
        next = CameraController(
          _cameras[_lens],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await next.initialize();
        await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
        if (!mounted || !widget.active || generation != _generation) {
          await next.dispose();
          return;
        }
        setState(() {
          _controller = next;
          _loading = false;
        });
      } catch (error) {
        await next?.dispose();
        if (mounted && generation == _generation) {
          setState(() {
            _loading = false;
            _error = error is CameraException && error.code.contains('Access')
                ? '카메라 권한을 확인해 주세요.\n사진첩에서도 한 끼를 고를 수 있어요.'
                : '촬영 버튼으로 카메라를 열거나\n사진첩에서 한 끼를 골라 주세요.';
          });
        }
      }
    });
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (_shooting) return;
    if (controller == null || !controller.value.isInitialized) {
      widget.onCamera();
      return;
    }
    setState(() => _shooting = true);
    try {
      final photo = await controller.takePicture();
      await pause();
      if (mounted) await widget.onPhoto(File(photo.path));
    } catch (_) {
      if (mounted) toast(context, '사진을 담지 못했어요. 다시 촬영해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _shooting = false);
        if (widget.active) unawaited(resume());
      }
    }
  }

  Future<void> _flip() async {
    if (_shooting || _loading || _cameras.length < 2) return;
    final direction = _controller?.description.lensDirection;
    final index = _cameras.indexWhere((c) => c.lensDirection != direction);
    _lens = index < 0 ? (_lens + 1) % _cameras.length : index;
    await pause();
    if (mounted && widget.active) await resume();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mealCameraRoutes.unsubscribe(this);
    _generation++;
    unawaited(
      _enqueue(() async {
        final old = _controller;
        _controller = null;
        await old?.dispose();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final height =
        (MediaQuery.sizeOf(context).height * .42).clamp(260.0, 410.0) + top;
    final controller = _controller;
    final live = controller?.value.isInitialized == true;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '한 끼 바로 촬영',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.demo)
              Image.asset('assets/photos/bowl.jpg', fit: BoxFit.cover)
            else if (live)
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller!.value.previewSize!.height,
                    height: controller.value.previewSize!.width,
                    child: CameraPreview(controller),
                  ),
                ),
              )
            else
              const ColoredBox(color: sky),
            if (live || widget.demo)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x55000000),
                      Colors.transparent,
                      Color(0x44000000),
                    ],
                    stops: [0, .35, 1],
                  ),
                ),
              ),
            Positioned(top: top + 4, left: 0, right: 0, child: widget.header),
            if (_loading)
              const Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (!live && !widget.demo)
              Positioned(
                top: top + 76,
                left: 32,
                right: 32,
                child: Column(
                  children: [
                    const CuteIcon(MealGlyph.rooms, size: 60),
                    const SizedBox(height: 10),
                    Text(
                      _error ?? '지금 먹는 한 끼를 담아볼까요?',
                      textAlign: TextAlign.center,
                      style: type(13, color: muted),
                    ),
                    if (_error != null)
                      TextButton(
                        onPressed: resume,
                        child: const Text('카메라 다시 연결'),
                      ),
                  ],
                ),
              ),
            Positioned(
              bottom: 99,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: live || widget.demo ? const Color(0x66000000) : milk,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    widget.demo ? '촬영 화면 미리보기' : '오늘의 한 끼, 찰칵',
                    style: type(
                      12,
                      color: live || widget.demo ? Colors.white : ink,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 18,
              left: 36,
              right: 36,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _roundAction('기존 사진 고르기', MealGlyph.album, widget.onGallery),
                  Semantics(
                    button: true,
                    label: '식사 사진 촬영',
                    enabled: !_shooting,
                    child: GestureDetector(
                      onTap: _shooting ? null : _takePhoto,
                      child: Container(
                        width: 68,
                        height: 68,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: milk,
                          shape: BoxShape.circle,
                          border: Border.all(color: peach, width: 3),
                        ),
                        child: _shooting
                            ? const Center(
                                child: SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Center(
                                child: CuteIcon(MealGlyph.rooms, size: 39),
                              ),
                      ),
                    ),
                  ),
                  _roundAction(
                    '카메라 전환',
                    MealGlyph.flip,
                    live && _cameras.length > 1 && !_loading && !_shooting
                        ? _flip
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundAction(String label, MealGlyph icon, VoidCallback? action) =>
      IconButton(
        tooltip: label,
        onPressed: action,
        style: IconButton.styleFrom(
          backgroundColor: milk,
          disabledBackgroundColor: milk,
          fixedSize: const Size(46, 46),
        ),
        icon: CuteIcon(icon, size: 23),
      );
}
