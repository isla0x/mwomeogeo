import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';

const milk = Color(0xfffaf9f6);
const cherry = Color(0xffa63d4e);
const ink = Color(0xff272420);
const muted = Color(0xff687580);
const sky = Color(0xffeaf1f5);
const line = Color(0xffe3e5e5);
const soft = Color(0xfff3f4f3);
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
  fontSize: size,
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
      backgroundColor: cherry,
      disabledBackgroundColor: line,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: type(14, color: Colors.white, weight: FontWeight.w500),
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 10),
                Icon(icon, size: 16),
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
      style: type(
        size * .37,
        color: const Color(0xff526c80),
        weight: FontWeight.w500,
      ),
    ),
  );
}

class MealPhoto extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final image = post.photo.startsWith('asset:')
        ? Image.asset(
            'assets/photos/${post.photo.substring(6)}.jpg',
            fit: BoxFit.cover,
          )
        : post.isCloud
        ? FutureBuilder(
            future: store.cloud.photoBytes(post.photo.substring(6)),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const PhotoFallback();
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
                errorBuilder: (_, _, _) => const PhotoFallback(),
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
  const PhotoFallback({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: sky,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.photo, color: muted),
          const SizedBox(height: 8),
          Text('사진을 불러오지 못했어요', style: type(11, color: muted)),
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
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
      ),
    );
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: milk,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: type(23, weight: FontWeight.w500)),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  ),
);
