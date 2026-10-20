import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'design.dart';
import 'models.dart';
import 'store.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.store,
    required this.initialMeal,
  });
  final MealStore store;
  final int initialMeal;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late int meal = widget.initialMeal;
  File? photo;
  bool busy = false;
  bool success = false;
  final caption = TextEditingController();
  late Set<String> recipients = {widget.store.tableId};
  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  Future<void> pick(ImageSource source) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final selected = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (selected != null && mounted) {
        setState(() => photo = File(selected.path));
      }
    } catch (_) {
      if (mounted) {
        toast(
          context,
          source == ImageSource.camera
              ? '카메라를 열지 못했어요. 설정에서 카메라 권한을 확인하거나 사진을 골라 주세요.'
              : '사진을 불러오지 못했어요. 다시 골라 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (photo == null || recipients.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await widget.store.saveMeal(
        source: photo!,
        meal: meal,
        caption: caption.text.trim(),
        tableIds: recipients.toList(),
      );
      if (mounted) setState(() => success = true);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      backgroundColor: milk,
      appBar: AppBar(
        backgroundColor: milk,
        foregroundColor: ink,
        leadingWidth: 72,
        leading: TextButton(
          onPressed: busy
              ? null
              : () => Navigator.pop(context, success ? meal : null),
          child: Text(success ? '닫기' : '취소', style: type(14, color: muted)),
        ),
        title: Text(
          success ? '한 끼의 안부' : '한 끼 남기기',
          style: type(17, weight: FontWeight.w500),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: success
            ? successView()
            : photo == null
            ? camera()
            : compose(),
      ),
    ),
  );
  Widget mealSelector() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Semantics(
              selected: meal == i,
              button: true,
              child: InkWell(
                onTap: busy ? null : () => setState(() => meal = i),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: meal == i ? sky : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    mealNames[i],
                    style: type(
                      14,
                      color: meal == i ? cherry : ink,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget camera() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        children: [
          mealSelector(),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            height: (constraints.maxHeight * .46).clamp(180.0, 350.0),
            decoration: BoxDecoration(
              color: sky.withValues(alpha: .65),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.camera, size: 42, color: muted),
                const SizedBox(height: 20),
                Text(
                  '오늘의 한 끼를 담아주세요.',
                  style: type(17, weight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text('잘 차리지 않아도 괜찮아요.', style: type(13, color: muted)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            '식사 사진 촬영',
            onPressed: () => pick(ImageSource.camera),
            busy: busy,
            icon: CupertinoIcons.camera,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: busy ? null : () => pick(ImageSource.gallery),
            icon: const Icon(CupertinoIcons.photo, size: 18),
            label: const Text('기존 사진 고르기'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.lock_shield, size: 14, color: muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text('사진첩에는 저장하지 않아요', style: type(12, color: muted)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> changePhoto() => showAppSheet(
    context,
    title: '사진 바꾸기',
    child: Column(
      children: [
        ListTile(
          leading: const Icon(CupertinoIcons.camera),
          title: const Text('다시 촬영하기'),
          onTap: () {
            Navigator.pop(context);
            pick(ImageSource.camera);
          },
        ),
        ListTile(
          leading: const Icon(CupertinoIcons.photo),
          title: const Text('사진에서 고르기'),
          onTap: () {
            Navigator.pop(context);
            pick(ImageSource.gallery);
          },
        ),
      ],
    ),
  );

  Widget compose() => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.25,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(photo!, fit: BoxFit.cover),
              Positioned(
                right: 16,
                bottom: 16,
                child: TextButton.icon(
                  onPressed: busy ? null : changePhoto,
                  style: TextButton.styleFrom(
                    backgroundColor: milk,
                    foregroundColor: ink,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.photo, size: 17),
                  label: Text('사진 바꾸기', style: type(12)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              mealSelector(),
              const SizedBox(height: 26),
              Text('오늘의 한마디', style: type(13, color: muted)),
              const SizedBox(height: 9),
              TextField(
                controller: caption,
                maxLength: 80,
                minLines: 2,
                maxLines: 4,
                style: type(14),
                decoration: const InputDecoration(hintText: '오늘은 뭐가 제일 맛있었어?'),
              ),
              const SizedBox(height: 18),
              Text('함께 볼 식탁', style: type(13, color: muted)),
              const SizedBox(height: 8),
              for (final table in widget.store.tables)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    selected: recipients.contains(table.id),
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: busy
                          ? null
                          : () => setState(() {
                              if (recipients.contains(table.id)) {
                                recipients.remove(table.id);
                              } else {
                                recipients.removeWhere(
                                  (id) =>
                                      id.startsWith('local-') == table.isCloud,
                                );
                                if (recipients.length < 5)
                                  recipients.add(table.id);
                                else
                                  toast(context, '한 번에 식탁 5개까지 선택할 수 있어요.');
                              }
                            }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: line),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(table.name, style: type(14))),
                            Icon(
                              recipients.contains(table.id)
                                  ? CupertinoIcons.checkmark_alt_circle_fill
                                  : CupertinoIcons.circle,
                              size: 23,
                              color: recipients.contains(table.id)
                                  ? cherry
                                  : line,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              PrimaryButton(
                '식탁에 남기기',
                onPressed: recipients.isEmpty ? null : save,
                busy: busy,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('선택한 식탁에만 나눠요.', style: type(11, color: muted)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget successView() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
    child: Column(
      children: [
        Container(
          width: 115,
          height: 115,
          decoration: const BoxDecoration(color: sky, shape: BoxShape.circle),
          child: const Icon(
            CupertinoIcons.tray,
            size: 48,
            color: Color(0xff6b899f),
          ),
        ),
        const SizedBox(height: 30),
        Text(
          '오늘의 한 끼,',
          style: type(29, weight: FontWeight.w500, spacing: -1.4),
        ),
        Text(
          '안부로 놓아두었어요.',
          style: type(
            28,
            color: cherry,
            weight: FontWeight.w500,
            spacing: -1.4,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '별일 없는 하루의 한 끼가\n누군가에겐 반가운 소식이니까.',
          textAlign: TextAlign.center,
          style: type(14, color: muted, height: 1.9),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            recipients
                .map(
                  (id) =>
                      widget.store.tables.firstWhere((t) => t.id == id).name,
                )
                .join(' · '),
            textAlign: TextAlign.center,
            style: type(14),
          ),
        ),
        const SizedBox(height: 25),
        PrimaryButton(
          '우리 식탁으로 돌아가기',
          onPressed: () => Navigator.pop(context, meal),
        ),
        if (recipients.every((id) => id.startsWith('local-')))
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '지금은 이 기기에 보관했어요.\n식탁을 연결하면 가까운 사람과 함께 볼 수 있어요.',
              textAlign: TextAlign.center,
              style: type(11, color: muted, height: 1.8),
            ),
          ),
      ],
    ),
  );
}
