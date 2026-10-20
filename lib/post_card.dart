import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'design.dart';
import 'models.dart';
import 'store.dart';

class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, required this.store});
  final MealPost post;
  final MealStore store;
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
    final hungry = p.reactions.contains('$user:yum');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Row(
            children: [
              Avatar(p.author, size: 31),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.author, style: type(13, weight: FontWeight.w500)),
                    Text(
                      p.isDemo
                          ? '회사에서 남긴 한 끼 · 예시'
                          : p.isCloud
                          ? '함께 나눈 한 끼'
                          : '내가 남긴 한 끼',
                      style: type(10, color: muted),
                    ),
                  ],
                ),
              ),
              Text(timeLabel(p.date), style: type(11, color: muted)),
              if (!p.isDemo)
                PopupMenuButton<String>(
                  tooltip: '기록 메뉴',
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  onSelected: (value) {
                    if (value == 'share') {
                      sharePhoto();
                    } else {
                      deletePost();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Text('사진과 한마디 공유'),
                    ),
                    if (!p.isCloud || p.authorId == s.cloud.userId)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('기록 삭제'),
                      ),
                  ],
                ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => showAppSheet(
            context,
            title: '${mealNames[p.meal]}의 기록',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: MealPhoto(p, s, edition: false),
                ),
                const SizedBox(height: 16),
                Text(p.caption, style: type(15)),
                const SizedBox(height: 12),
                Text(
                  '${dayLabel(p.date)} ${timeLabel(p.date)}',
                  style: type(11, color: muted),
                ),
              ],
            ),
          ),
          child: MealPhoto(
            p,
            s,
            height: (MediaQuery.sizeOf(context).width - 48) * .79,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(
            p.caption.isEmpty ? '오늘도 잘 챙겨 먹었어요.' : p.caption,
            style: type(14),
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: busy ? null : () => react('heart'),
              icon: Icon(
                liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                size: 18,
                color: liked ? cherry : muted,
              ),
              label: Text(
                '잘 먹었네${p.reactions.where((r) => r.endsWith(':heart')).isNotEmpty ? '  ${p.reactions.where((r) => r.endsWith(':heart')).length}' : ''}',
                style: type(12, color: liked ? cherry : muted),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
              ),
            ),
            const SizedBox(width: 18),
            TextButton(
              onPressed: busy ? null : () => react('yum'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                '한 입만${hungry ? ' · 1' : ''}',
                style: type(12, color: hungry ? cherry : muted),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '한마디 남기기',
              onPressed: () => openComments(context, p, s),
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.chat_bubble,
                    size: 18,
                    color: muted,
                  ),
                  if (p.comments.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text('${p.comments.length}', style: type(11, color: muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 기록을 삭제할까요?'),
        content: const Text('삭제한 식사 기록과 댓글은 복구할 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: cherry)),
          ),
        ],
      ),
    );
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
