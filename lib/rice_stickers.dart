import 'package:flutter/material.dart';

import 'design.dart';
import 'models.dart';
import 'store.dart';

class RiceStickerArt extends StatelessWidget {
  const RiceStickerArt(this.variant, {super.key});
  final int variant;
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: Transform.rotate(
          angle: variant == 1 ? -.22 : 0,
          child: const CustomPaint(painter: RiceFriendsPainter()),
        ),
      ),
      if (variant != 4)
        Positioned(
          right: 0,
          top: 0,
          child: SizedBox(
            width: 22,
            height: 22,
            child: variant == 0
                ? const CustomPaint(painter: _SpoonPainter())
                : CuteIcon(
                    [
                      MealGlyph.bowl,
                      MealGlyph.moon,
                      MealGlyph.heart,
                      MealGlyph.album,
                    ][variant],
                    size: 22,
                  ),
          ),
        ),
    ],
  );
}

class _SpoonPainter extends CustomPainter {
  const _SpoonPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xff5d3f2a)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(Rect.fromLTWH(10, 1, 9, 12), Paint()..color = butter);
    canvas.drawOval(Rect.fromLTWH(10, 1, 9, 12), p);
    canvas.drawLine(const Offset(12, 13), const Offset(4, 21), p);
  }

  @override
  bool shouldRepaint(_SpoonPainter oldDelegate) => false;
}

class StickerPhoto extends StatelessWidget {
  const StickerPhoto(this.post, this.store, {super.key, this.stickers});
  final MealPost post;
  final MealStore store;
  final List<RiceSticker>? stickers;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Stack(
      children: [
        Positioned.fill(child: MealPhoto(post, store, edition: false)),
        for (final sticker in stickers ?? post.stickers)
          Positioned(
            left: (box.maxWidth - box.maxWidth * sticker.scale) * sticker.x,
            top:
                (box.maxHeight - box.maxWidth * sticker.scale * .7) * sticker.y,
            width: box.maxWidth * sticker.scale,
            height: box.maxWidth * sticker.scale * .7,
            child: IgnorePointer(
              child: Semantics(
                label:
                    '${sticker.name}의 ${riceStickerNames[sticker.variant]} 밥풀',
                child: RiceStickerArt(sticker.variant),
              ),
            ),
          ),
      ],
    ),
  );
}

Future<void> editRiceSticker(
  BuildContext context,
  MealPost post,
  MealStore store,
) => showAppSheet(
  context,
  title: '${post.author} 사진에 밥풀 붙이기',
  child: _StickerEditor(post, store),
);

class _StickerEditor extends StatefulWidget {
  const _StickerEditor(this.post, this.store);
  final MealPost post;
  final MealStore store;
  @override
  State<_StickerEditor> createState() => _StickerEditorState();
}

class _StickerEditorState extends State<_StickerEditor> {
  late final uid = widget.post.isCloud ? widget.store.cloud.userId! : 'local';
  late RiceSticker? selected = widget.post.stickers
      .where((s) => s.userId == uid)
      .firstOrNull;
  bool busy = false;
  void change({int? variant, double? x, double? y, double? scale}) =>
      setState(() {
        selected = RiceSticker(
          uid,
          widget.store.name,
          variant ?? selected?.variant ?? 2,
          (x ?? selected?.x ?? .85).clamp(0, 1).toDouble(),
          (y ?? selected?.y ?? .85).clamp(0, 1).toDouble(),
          scale ?? selected?.scale ?? .24,
        );
      });
  Future<void> save() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.store.putSticker(widget.post, selected);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        toast(context, '$e');
        setState(() => busy = false);
      }
    }
  }

  Widget _choice({
    required Widget label,
    required bool selected,
    VoidCallback? onTap,
  }) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? peach : soft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minWidth: 54, minHeight: 48),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? cherry : line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: label,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: busy ? null : save,
          child: Text(busy ? '붙이는 중…' : '붙이기'),
        ),
      ),
      AspectRatio(
        aspectRatio: 1.1,
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            onPanUpdate: busy || selected == null
                ? null
                : (d) => change(
                    x:
                        selected!.x +
                        d.delta.dx / (box.maxWidth * (1 - selected!.scale)),
                    y:
                        selected!.y +
                        d.delta.dy /
                            (box.maxHeight -
                                box.maxWidth * selected!.scale * .7),
                  ),
            child: StickerPhoto(
              widget.post,
              widget.store,
              stickers: [
                ...widget.post.stickers.where((s) => s.userId != uid),
                ?selected,
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text('원하는 밥풀을 고르고 사진 위에서 움직여 주세요.', style: type(12, color: muted)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _choice(
            label: const Text('없음'),
            selected: selected == null,
            onTap: busy ? null : () => setState(() => selected = null),
          ),
          for (var i = 0; i < riceStickerNames.length; i++)
            _choice(
              label: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 46, height: 34, child: RiceStickerArt(i)),
                  Text(riceStickerNames[i], style: type(11)),
                ],
              ),
              selected: selected?.variant == i,
              onTap: busy ? null : () => change(variant: i),
            ),
        ],
      ),
      if (selected != null)
        Row(
          children: [
            Text('크기', style: type(12)),
            Expanded(
              child: Slider(
                value: selected!.scale,
                min: .14,
                max: .38,
                onChanged: busy ? null : (v) => change(scale: v),
              ),
            ),
          ],
        ),
    ],
  );
}
