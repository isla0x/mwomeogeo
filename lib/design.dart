import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'app_icons.dart';
export 'app_icons.dart';

const milk = Color(0xfffffcf8);
const cherry = Color(0xffb95236);
const ink = Color(0xff342e2d);
const muted = Color(0xff7c6d62);
const sky = Color(0xffffeee1);
const line = Color(0xffeee6df);
const soft = Color(0xfffff5ed);
const peach = Color(0xffffddcb);
const butter = Color(0xfff2ce79);
const mealIcons = [
  CupertinoIcons.sunrise,
  CupertinoIcons.sun_max,
  CupertinoIcons.moon,
];
TextStyle type(
  double size, {
  Color color = ink,
  FontWeight weight = FontWeight.w400,
  double spacing = -.3,
  double height = 1.5,
}) => TextStyle(
  fontFamily: 'NanumSquareRound',
  fontFamilyFallback: const ['Pretendard'],
  fontSize: size.clamp(11.0, 32.0).toDouble(),
  color: color,
  fontWeight: weight,
  letterSpacing: spacing,
  height: height,
);

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: peach,
      disabledBackgroundColor: line,
      foregroundColor: ink,
      elevation: 0,
      minimumSize: const Size(double.infinity, 50),
      shape: const StadiumBorder(),
    ),
    child: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: ink),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(label, style: type(14, weight: FontWeight.w500)),
              ),
              if (icon != null) ...[
                const SizedBox(width: 10),
                AppIcon(icon, size: 18),
              ],
            ],
          ),
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 32});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: sky, shape: BoxShape.circle),
    child: Text(
      name.isEmpty ? '나' : name.characters.first,
      style: type(size * .37, color: ink, weight: FontWeight.w500),
    ),
  );
}

/// Small visible artwork, with a generous accessible control area.
class GrainToggle extends StatelessWidget {
  const GrainToggle({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    toggled: value,
    enabled: onChanged != null,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 56,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 27,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? peach : line,
                borderRadius: BorderRadius.circular(20),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 19,
                  height: 21,
                  decoration: BoxDecoration(
                    color: milk,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: value
                      ? const Center(child: CuteIcon(MealGlyph.check, size: 12))
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: line, width: .6),
    ),
    child: child,
  );
}

class MealPhoto extends StatefulWidget {
  const MealPhoto(
    this.post,
    this.store, {
    super.key,
    this.height,
    this.edition = true,
  });
  final MealPost post;
  final MealStore store;
  final double? height;
  final bool edition;
  @override
  State<MealPhoto> createState() => _MealPhotoState();
}

class _MealPhotoState extends State<MealPhoto> {
  MealPost get post => widget.post;
  MealStore get store => widget.store;
  double? get height => widget.height;
  bool get edition => widget.edition;
  Future<Uint8List>? photo;

  Future<Uint8List>? loadPhoto({bool refresh = false}) => post.isCloud
      ? store.cloud.photoBytes(post.photo.substring(6), refresh: refresh)
      : null;

  @override
  void initState() {
    super.initState();
    photo = loadPhoto();
  }

  @override
  void didUpdateWidget(MealPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != post || oldWidget.store != store) {
      photo = loadPhoto();
    }
  }

  void retry() {
    setState(() {
      photo = loadPhoto(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final image = post.photo.startsWith('asset:')
        ? Image.asset(
            'assets/photos/${post.photo.substring(6)}.jpg',
            fit: BoxFit.cover,
          )
        : post.isCloud
        ? FutureBuilder<Uint8List>(
            future: photo,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return PhotoFallback(
                  message: '${snapshot.error}',
                  onRetry: retry,
                );
              }
              if (!snapshot.hasData) {
                return const ColoredBox(
                  color: sky,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                );
              }
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    PhotoFallback(message: '사진 파일을 표시하지 못했어요.', onRetry: retry),
              );
            },
          )
        : Image.file(
            File('${store.directory.path}/${post.photo}'),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const PhotoFallback(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (edition)
              Positioned(
                left: 14,
                top: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${mealEditions[post.meal]}     0${post.meal + 1}',
                    style: type(9, color: muted, spacing: 1.4),
                  ),
                ),
              ),
            if (post.isDemo && edition)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('예시 사진', style: type(10, color: muted)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PhotoFallback extends StatelessWidget {
  const PhotoFallback({
    super.key,
    this.message = '사진을 불러오지 못했어요',
    this.onRetry,
  });
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: sky,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppIcon(CupertinoIcons.photo, color: muted),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: type(11, color: muted),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('다시 불러오기')),
        ],
      ),
    ),
  );
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: type(13, color: Colors.white)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
      ),
    );
}

// All app-owned modal surfaces share the same neutral, untinted shell.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  String? subtitle,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  barrierColor: ink.withValues(alpha: .30),
  backgroundColor: Colors.transparent,
  elevation: 0,
  constraints: const BoxConstraints(maxWidth: 544),
  builder: (context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.fromLTRB(
      12,
      12,
      12,
      MediaQuery.viewInsetsOf(context).bottom + 12,
    ),
    child: SafeArea(
      top: false,
      child: Material(
        color: milk,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: type(21, weight: FontWeight.w600, spacing: -.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: soft,
                      minimumSize: const Size(44, 44),
                    ),
                    icon: const AppIcon(
                      CupertinoIcons.xmark,
                      size: 15,
                      color: muted,
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: type(13, color: muted)),
              ],
              const SizedBox(height: 20),
              child,
            ],
          ),
        ),
      ),
    ),
  ),
);

/// A single accessible row for actions and single/multiple selection.
class AppOption extends StatelessWidget {
  const AppOption({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.selected,
    this.destructive = false,
  });
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool? selected;
  final bool destructive;
  @override
  Widget build(BuildContext context) {
    final active = selected == true;
    final accent = active || destructive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: active ? soft : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
            side: BorderSide(color: active ? peach : line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent ? sky : soft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AppIcon(
                      icon,
                      size: 20,
                      color: accent ? cherry : muted,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: type(
                            14,
                            color: destructive ? cherry : ink,
                            weight: FontWeight.w500,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(subtitle!, style: type(11, color: muted)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppIcon(
                    selected == null
                        ? CupertinoIcons.chevron_right
                        : active
                        ? CupertinoIcons.checkmark_alt_circle_fill
                        : CupertinoIcons.circle,
                    size: selected == null ? 13 : 22,
                    color: active
                        ? cherry
                        : selected == null
                        ? muted
                        : line,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> confirmDelete(
  BuildContext context, {
  String title = '이 기록을 삭제할까요?',
  String description = '식사 사진과 댓글이 함께 사라져요.\n삭제한 기록은 되돌릴 수 없어요.',
  String action = '삭제',
}) => showDialog<bool>(
  context: context,
  barrierColor: ink.withValues(alpha: .30),
  builder: (context) => Dialog(
    backgroundColor: milk,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: sky,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const AppIcon(
                CupertinoIcons.trash,
                color: cherry,
                size: 22,
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: type(20, weight: FontWeight.w600, spacing: -.7)),
            const SizedBox(height: 10),
            Text(description, style: type(13, color: muted, height: 1.7)),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ink,
                      side: const BorderSide(color: line),
                      minimumSize: const Size(0, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('취소', style: type(14, weight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    action,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
