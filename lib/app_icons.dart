import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'rice_reference.dart';

/// Original vector artwork: no icon font or raster scaling for the app's core UI.
enum MealGlyph {
  table,
  camera,
  calendar,
  settings,
  sunrise,
  bowl,
  moon,
  bell,
  heart,
  comment,
  album,
  addPhoto,
  flip,
  rooms,
  invite,
  close,
  grain,
  plus,
  check,
  trash,
  share,
  copy,
}

final _glyphs = <IconData, MealGlyph>{
  CupertinoIcons.house: MealGlyph.table,
  CupertinoIcons.camera: MealGlyph.camera,
  CupertinoIcons.camera_fill: MealGlyph.camera,
  CupertinoIcons.calendar: MealGlyph.calendar,
  CupertinoIcons.doc_plaintext: MealGlyph.calendar,
  CupertinoIcons.gear: MealGlyph.settings,
  CupertinoIcons.sunrise: MealGlyph.sunrise,
  CupertinoIcons.sun_max: MealGlyph.bowl,
  CupertinoIcons.moon: MealGlyph.moon,
  CupertinoIcons.bell: MealGlyph.bell,
  CupertinoIcons.bell_fill: MealGlyph.bell,
  CupertinoIcons.heart: MealGlyph.heart,
  CupertinoIcons.heart_fill: MealGlyph.heart,
  CupertinoIcons.chat_bubble: MealGlyph.comment,
  CupertinoIcons.photo: MealGlyph.album,
  CupertinoIcons.person_2: MealGlyph.rooms,
  CupertinoIcons.xmark: MealGlyph.close,
  CupertinoIcons.plus: MealGlyph.plus,
  CupertinoIcons.checkmark_alt_circle_fill: MealGlyph.check,
  CupertinoIcons.tray: MealGlyph.table,
  CupertinoIcons.trash: MealGlyph.trash,
  CupertinoIcons.square_arrow_up: MealGlyph.share,
  CupertinoIcons.paperplane: MealGlyph.share,
  CupertinoIcons.doc_on_doc: MealGlyph.copy,
};

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = _glyphs[icon];
    if (glyph == null) {
      return Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    }
    return CuteIcon(
      glyph,
      size: size ?? 20,
      color: color,
      filled: icon == CupertinoIcons.heart_fill,
      semanticLabel: semanticLabel,
    );
  }
}

class CuteIcon extends StatelessWidget {
  const CuteIcon(
    this.glyph, {
    super.key,
    this.size = 20,
    this.color,
    this.filled = true,
    this.semanticLabel,
  });
  final MealGlyph glyph;
  final double size;
  final Color? color;
  final bool filled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    image: semanticLabel != null,
    excludeSemantics: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: glyph == MealGlyph.rooms || glyph == MealGlyph.table
            ? RiceFriendsPainter(color: color)
            : MealIconPainter(glyph, color, filled),
      ),
    ),
  );
}

/// Traced from the approved reference, shared by the UI and launcher assets.
class RiceFriendsPainter extends CustomPainter {
  const RiceFriendsPainter({this.color});
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    paintRiceReference(
      canvas,
      ink: color == Colors.white ? Colors.white : null,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(RiceFriendsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class MealIconPainter extends CustomPainter {
  const MealIconPainter(this.glyph, this.color, this.filled);
  final MealGlyph glyph;
  final Color? color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 32, size.height / 32);
    final dark = color == Colors.white;
    final cocoa = dark ? Colors.white : const Color(0xff725b49);
    final peach = dark
        ? Colors.white.withValues(alpha: .22)
        : const Color(0xfff2ae92);
    final butter = dark
        ? Colors.white.withValues(alpha: .18)
        : const Color(0xfff2ce79);
    const ivory = Color(0xfffffcf8);
    final pen = Paint()
      ..color = cocoa
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void path(Path p, [Color? fill]) {
      if (fill != null) canvas.drawPath(p, Paint()..color = fill);
      canvas.drawPath(p, pen);
    }

    void line(double x, double y, double a, double b) =>
        canvas.drawLine(Offset(x, y), Offset(a, b), pen);
    void circle(
      double x,
      double y,
      double r,
      Color fill, {
      bool outline = true,
    }) {
      canvas.drawCircle(Offset(x, y), r, Paint()..color = fill);
      if (outline) canvas.drawCircle(Offset(x, y), r, pen);
    }

    void box(Rect rect, double radius, Color fill) {
      final r = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(r, Paint()..color = fill);
      canvas.drawRRect(r, pen);
    }

    void smile(double x, double y) {
      circle(x - 3, y - 2, .8, cocoa, outline: false);
      circle(x + 3, y - 2, .8, cocoa, outline: false);
      canvas.drawPath(
        Path()
          ..moveTo(x - 2, y + 1)
          ..quadraticBezierTo(x, y + 4, x + 2, y + 1),
        pen,
      );
    }

    void grain(double x, double y, double scale) {
      canvas.save();
      canvas.translate(x, y);
      canvas.scale(scale);
      path(
        Path()
          ..moveTo(-2, 0)
          ..cubicTo(-7, -.2, -7, -4, -4.3, -9.3)
          ..cubicTo(-2.2, -13.4, .1, -15.2, 2.5, -13.8)
          ..cubicTo(5.7, -12, 7, -6.5, 6, -3)
          ..cubicTo(5.2, -.4, 2, .4, -2, 0)
          ..close(),
        ivory,
      );
      circle(-1.6, -6, .6, cocoa, outline: false);
      circle(1.6, -6, .6, cocoa, outline: false);
      canvas.restore();
    }

    void bowl({bool face = false}) {
      path(
        Path()
          ..moveTo(5, 14)
          ..quadraticBezierTo(4, 10, 9, 10)
          ..quadraticBezierTo(10, 6, 14, 9)
          ..quadraticBezierTo(17, 5, 20, 9)
          ..quadraticBezierTo(26, 8, 26, 14)
          ..close(),
        ivory,
      );
      path(
        Path()
          ..moveTo(3, 14)
          ..lineTo(29, 14)
          ..quadraticBezierTo(28, 27, 16, 27)
          ..quadraticBezierTo(4, 27, 3, 14)
          ..close(),
        butter,
      );
      line(12, 29, 20, 29);
      if (face) smile(16, 20);
    }

    switch (glyph) {
      case MealGlyph.table:
      case MealGlyph.rooms:
        RiceFriendsPainter(color: color).paint(canvas, const Size(32, 32));
      case MealGlyph.grain:
        grain(16, 29, 1.65);
      case MealGlyph.bowl:
        bowl();
        path(
          Path()
            ..moveTo(12, 6)
            ..quadraticBezierTo(9, 3, 12, 1),
        );
        path(
          Path()
            ..moveTo(20, 6)
            ..quadraticBezierTo(17, 3, 20, 1),
        );
      case MealGlyph.camera:
        path(
          Path()
            ..moveTo(7, 9)
            ..lineTo(10, 9)
            ..quadraticBezierTo(11, 4, 15, 5)
            ..lineTo(19, 5)
            ..quadraticBezierTo(22, 5, 23, 9)
            ..lineTo(26, 9)
            ..quadraticBezierTo(30, 9, 30, 14)
            ..lineTo(29, 25)
            ..quadraticBezierTo(29, 28, 24, 28)
            ..lineTo(7, 28)
            ..quadraticBezierTo(2, 28, 2, 23)
            ..lineTo(2, 14)
            ..quadraticBezierTo(2, 9, 7, 9)
            ..close(),
          butter,
        );
        circle(16, 18, 7, peach);
        circle(16, 18, 4.2, ivory);
        circle(25, 12, 1, ivory, outline: false);
      case MealGlyph.calendar:
        box(const Rect.fromLTWH(4, 7, 24, 23), 5, ivory);
        line(4, 14, 28, 14);
        box(const Rect.fromLTWH(9, 2, 3, 9), 1.5, peach);
        box(const Rect.fromLTWH(21, 2, 3, 9), 1.5, peach);
        canvas.drawOval(
          const Rect.fromLTWH(13, 19, 7, 8),
          Paint()..color = butter,
        );
      case MealGlyph.settings:
        final p = Path();
        for (var i = 0; i <= 120; i++) {
          final a = i * 2 * math.pi / 120;
          final r = 12 + 1.8 * math.cos(a * 6);
          final point = Offset(16 + math.cos(a) * r, 16 + math.sin(a) * r);
          if (i == 0) {
            p.moveTo(point.dx, point.dy);
          } else {
            p.lineTo(point.dx, point.dy);
          }
        }
        p.close();
        path(p, butter);
        circle(16, 16, 6, peach);
        circle(16, 16, 3.4, ivory);
      case MealGlyph.sunrise:
        path(
          Path()
            ..moveTo(7, 24)
            ..arcToPoint(const Offset(25, 24), radius: const Radius.circular(9))
            ..close(),
          butter,
        );
        for (final a in [
          -math.pi,
          -3 * math.pi / 4,
          -math.pi / 2,
          -math.pi / 4,
          0.0,
        ]) {
          line(
            16 + 13 * math.cos(a),
            24 + 13 * math.sin(a),
            16 + 16 * math.cos(a),
            24 + 16 * math.sin(a),
          );
        }
        smile(16, 21);
        line(3, 27, 29, 27);
      case MealGlyph.moon:
        path(
          Path()
            ..moveTo(21, 3)
            ..cubicTo(1, 0, -3, 25, 14, 29)
            ..quadraticBezierTo(25, 32, 29, 20)
            ..cubicTo(16, 25, 12, 12, 21, 3)
            ..close(),
          butter,
        );
        path(
          Path()
            ..moveTo(8, 18)
            ..quadraticBezierTo(11, 21, 14, 18),
        );
      case MealGlyph.bell:
        circle(16, 5, 2.4, peach);
        circle(16, 27, 3, butter);
        path(
          Path()
            ..moveTo(5, 24)
            ..quadraticBezierTo(9, 20, 8, 14)
            ..cubicTo(7, 2, 25, 2, 24, 14)
            ..quadraticBezierTo(23, 20, 27, 24)
            ..quadraticBezierTo(16, 28, 5, 24)
            ..close(),
          ivory,
        );
      case MealGlyph.heart:
        path(
          Path()
            ..moveTo(16, 28)
            ..cubicTo(8, 23, 1, 16, 3, 9)
            ..cubicTo(5, 2, 13, 3, 16, 9)
            ..cubicTo(20, 2, 28, 3, 29, 10)
            ..cubicTo(31, 17, 23, 24, 16, 28)
            ..close(),
          filled ? peach : ivory,
        );
      case MealGlyph.comment:
        path(
          Path()
            ..moveTo(8, 25)
            ..lineTo(4, 30)
            ..lineTo(4, 23)
            ..cubicTo(-6, 7, 8, 1, 20, 3)
            ..cubicTo(35, 5, 34, 24, 20, 26)
            ..quadraticBezierTo(13, 28, 8, 25)
            ..close(),
          butter,
        );
        circle(12, 15, 1.6, ivory, outline: false);
        circle(20, 15, 1.6, ivory, outline: false);
      case MealGlyph.album:
      case MealGlyph.addPhoto:
        if (glyph == MealGlyph.album) {
          box(const Rect.fromLTWH(8, 2, 22, 22), 5, peach);
        }
        box(const Rect.fromLTWH(2, 7, 24, 22), 5, ivory);
        path(
          Path()
            ..moveTo(5, 25)
            ..lineTo(11, 17)
            ..lineTo(16, 22)
            ..lineTo(20, 19)
            ..lineTo(24, 25)
            ..close(),
          butter,
        );
        circle(20, 13, 2.4, peach, outline: false);
        if (glyph == MealGlyph.addPhoto) {
          box(const Rect.fromLTWH(22, 21, 9, 4), 2, peach);
          box(const Rect.fromLTWH(24.5, 18.5, 4, 9), 2, peach);
        }
      case MealGlyph.flip:
        path(
          Path()
            ..moveTo(4, 13)
            ..cubicTo(8, 2, 23, 3, 27, 11)
            ..lineTo(28, 6)
            ..lineTo(30, 16)
            ..lineTo(21, 14)
            ..lineTo(25, 12),
          peach,
        );
        path(
          Path()
            ..moveTo(28, 20)
            ..cubicTo(24, 31, 9, 30, 5, 22)
            ..lineTo(4, 27)
            ..lineTo(2, 17)
            ..lineTo(11, 19)
            ..lineTo(7, 21),
          butter,
        );
      case MealGlyph.invite:
        circle(11, 10, 5, peach);
        circle(23, 12, 4, butter);
        path(
          Path()
            ..moveTo(2, 28)
            ..cubicTo(1, 12, 21, 12, 20, 28)
            ..close(),
          peach,
        );
        path(
          Path()
            ..moveTo(20, 28)
            ..lineTo(29, 28)
            ..quadraticBezierTo(31, 17, 23, 18),
          butter,
        );
        line(26, 2, 26, 8);
        line(23, 5, 29, 5);
      case MealGlyph.close:
        line(8, 8, 24, 24);
        line(24, 8, 8, 24);
      case MealGlyph.plus:
        line(16, 6, 16, 26);
        line(6, 16, 26, 16);
      case MealGlyph.check:
        path(
          Path()
            ..moveTo(7, 16)
            ..lineTo(13, 22)
            ..lineTo(25, 9),
        );
      case MealGlyph.trash:
        box(const Rect.fromLTWH(8, 9, 17, 20), 4, ivory);
        line(5, 8, 28, 8);
        box(const Rect.fromLTWH(12, 3, 9, 5), 2, peach);
        line(13, 14, 13, 24);
        line(20, 14, 20, 24);
      case MealGlyph.share:
        path(
          Path()
            ..moveTo(5, 19)
            ..lineTo(5, 28)
            ..lineTo(27, 28)
            ..lineTo(27, 19),
        );
        line(16, 22, 16, 3);
        line(9, 10, 16, 3);
        line(16, 3, 23, 10);
      case MealGlyph.copy:
        box(const Rect.fromLTWH(9, 3, 20, 22), 4, peach);
        box(const Rect.fromLTWH(3, 9, 20, 21), 4, ivory);
    }
  }

  @override
  bool shouldRepaint(MealIconPainter old) =>
      old.glyph != glyph || old.color != color || old.filled != filled;
}
