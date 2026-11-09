import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'design.dart';
import 'models.dart';
import 'store.dart';
import 'rice_stickers.dart';

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.store,
    this.compact = false,
    this.tile = false,
  });
  final MealPost post;
  final MealStore store;
  final bool compact;
  final bool tile;
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool busy = false;
  MealPost get p => widget.post;
  MealStore get s => widget.store;
  Future<void> react(String kind) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await s.react(p, kind);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = p.isCloud ? s.cloud.userId : 'local';
    final liked = p.reactions.contains('$user:heart');
    final likes = p.reactions.where((r) => r.endsWith(':heart')).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Semantics(
              button: true,
              label: '${mealNames[p.meal]} 사진 크게 보기',
              child: GestureDetector(
                onTap: openPhoto,
                child: AspectRatio(aspectRatio: 1.1, child: StickerPhoto(p, s)),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              right: 43,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: milk.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    p.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type(11, weight: FontWeight.w500),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                tooltip: '기록 메뉴',
                onPressed: busy ? null : openMenu,
                icon: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: milk.withValues(alpha: .94),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    CupertinoIcons.ellipsis,
                    size: 15,
                    color: muted,
                  ),
                ),
              ),
            ),
          ],
        ),
        caption(),
        if (p.stickers.isNotEmpty)
          Text(
            p.stickers.map((sticker) => '${sticker.name}의 밥풀').join(' · '),
            style: type(10, color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        Row(
          children: [
            if (p.isDemo || (p.isCloud && p.authorId != s.cloud.userId))
              IconButton(
                tooltip: '밥풀 콕 · 스티커',
                onPressed: busy ? null : riceActions,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 48),
                icon: const CuteIcon(MealGlyph.rooms, size: 23),
              ),
            Flexible(
              child: IconButton(
                tooltip: '잘 먹었네 $likes',
                onPressed: busy ? null : () => react('heart'),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                      size: 17,
                    ),
                    const SizedBox(width: 5),
                    Text('$likes', style: type(11, color: muted)),
                  ],
                ),
              ),
            ),
            Flexible(
              child: IconButton(
                tooltip: '한마디 남기기',
                onPressed: () => openComments(context, p, s),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CuteIcon(MealGlyph.comment, size: 17),
                    const SizedBox(width: 5),
                    Text('${p.comments.length}', style: type(11, color: muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> riceActions() async {
    final action = await showAppSheet<String>(
      context,
      title: '${p.author}에게 밥풀로',
      child: Column(
        children: [
          AppOption(
            label: '밥풀 콕 찌르기',
            subtitle: '밥 먹었어? 다정하게 안부를 보내요',
            icon: CupertinoIcons.bell,
            onTap: () => Navigator.pop(context, 'poke'),
          ),
          AppOption(
            label: '사진에 스티커 붙이기',
            subtitle: '상대 사진에 내 밥풀을 남겨요',
            icon: CupertinoIcons.heart,
            onTap: () => Navigator.pop(context, 'sticker'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'sticker') {
      await editRiceSticker(context, p, s);
    }
    if (action == 'poke') {
      setState(() => busy = true);
      try {
        if (!p.isDemo) {
          await s.nudges.send(
            p.tableIds.single,
            p.meal,
            requestId: newId(),
            recipientId: p.authorId,
          );
        }
        if (mounted) {
          toast(context, p.isDemo ? '미리보기 콕이에요.' : '${p.author}에게 콕 보냈어요.');
        }
      } catch (e) {
        if (mounted) toast(context, '$e');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
  }

  Widget caption() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(
      p.caption.isEmpty ? '오늘도 잘 챙겨 먹었어요.' : p.caption,
      maxLines: widget.compact ? 2 : null,
      overflow: widget.compact ? TextOverflow.ellipsis : null,
      style: type(widget.compact ? 12 : 14),
    ),
  );

  void openPhoto() => showAppSheet(
    context,
    title: '${mealNames[p.meal]}의 기록',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 1.1, child: StickerPhoto(p, s)),
        const SizedBox(height: 16),
        Text(p.caption.isEmpty ? '오늘도 잘 챙겨 먹었어요.' : p.caption, style: type(15)),
        const SizedBox(height: 12),
        Text(
          '${dayLabel(p.date)} ${timeLabel(p.date)}',
          style: type(11, color: muted),
        ),
        TextButton(
          onPressed: busy ? null : () => react('yum'),
          child: const Text('한 입만'),
        ),
      ],
    ),
  );

  Future<void> openMenu() async {
    final user = p.isCloud ? s.cloud.userId : 'local';
    final hungry = p.reactions.contains('$user:yum');
    final action = await showAppSheet<String>(
      context,
      title: '한 끼의 기록',
      subtitle: '${p.author} · ${mealNames[p.meal]} · ${timeLabel(p.date)}',
      child: Column(
        children: [
          AppOption(
            label: hungry ? '한 입만 취소' : '한 입만',
            subtitle: '맛있어 보이는 한 끼에 마음을 남겨요',
            icon: CupertinoIcons.heart,
            onTap: () => Navigator.pop(context, 'yum'),
          ),
          if (!p.isDemo)
            AppOption(
              label: '사진과 한마디 공유',
              subtitle: '소중한 한 끼를 다른 곳에도 전해요',
              icon: CupertinoIcons.square_arrow_up,
              onTap: () => Navigator.pop(context, 'share'),
            ),
          if (!p.isDemo && (!p.isCloud || p.authorId == s.cloud.userId)) ...[
            const SizedBox(height: 6),
            AppOption(
              label: '기록 삭제',
              subtitle: '사진과 댓글을 함께 지워요',
              icon: CupertinoIcons.trash,
              destructive: true,
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'yum':
        await react('yum');
      case 'share':
        await sharePhoto();
      case 'delete':
        await deletePost();
    }
  }

  Future<void> sharePhoto() async {
    try {
      File file;
      if (p.isCloud) {
        final bytes = await s.cloud.photoBytes(p.photo.substring(6));
        final extension = p.photo.endsWith('.png') ? 'png' : 'jpg';
        file = File(
          '${(await getTemporaryDirectory()).path}/${p.id}.$extension',
        );
        await file.writeAsBytes(bytes);
      } else {
        file = File('${s.directory.path}/${p.photo}');
      }
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${p.caption}\n뭐먹어? · ${mealNames[p.meal]}의 기록',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      if (mounted) toast(context, '공유를 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> deletePost() async {
    final confirmed = await confirmDelete(context);
    if (confirmed != true) return;
    try {
      await s.delete(p);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }
}

Future<void> openComments(
  BuildContext context,
  MealPost post,
  MealStore store,
) async {
  await showAppSheet(
    context,
    title: '한마디도 같이',
    child: _Comments(post: post, store: store),
  );
}

class _Comments extends StatefulWidget {
  const _Comments({required this.post, required this.store});
  final MealPost post;
  final MealStore store;
  @override
  State<_Comments> createState() => _CommentsState();
}

class _CommentsState extends State<_Comments> {
  final controller = TextEditingController();
  bool busy = false;
  List<MealComment> get comments =>
      widget.store.allPosts
          .where((p) => p.id == widget.post.id)
          .firstOrNull
          ?.comments ??
      widget.post.comments;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final text = controller.text.trim();
    if (text.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await widget.store.addComment(widget.post, text);
      controller.clear();
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (comments.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text('다정한 한마디를 먼저 남겨볼까요?', style: type(13, color: muted)),
        ),
      for (final c in comments)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(c.name, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: type(12, weight: FontWeight.w600)),
                    Text(c.text, style: type(14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      TextField(
        controller: controller,
        maxLength: 80,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => send(),
        decoration: const InputDecoration(
          hintText: '든든하게 먹었네 ❤️',
          labelText: '한마디',
        ),
      ),
      const SizedBox(height: 12),
      PrimaryButton('한마디 남기기', onPressed: send, busy: busy),
      if (widget.post.isDemo)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '미리보기 반응이에요. 실제로 전송되지 않아요.',
            style: type(11, color: muted),
          ),
        ),
    ],
  );
}
