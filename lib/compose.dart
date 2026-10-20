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
      backgroundColor: photo == null ? const Color(0xff242b33) : Colors.white,
      appBar: AppBar(
        backgroundColor: photo == null ? const Color(0xff242b33) : Colors.white,
        foregroundColor: photo == null ? Colors.white : ink,
        leading: IconButton(
          tooltip: '닫기',
          onPressed: busy
              ? null
              : () => Navigator.pop(context, success ? meal : null),
          icon: const Icon(CupertinoIcons.xmark, size: 20),
        ),
        title: Text(
          success
              ? '한 끼의 안부'
              : photo == null
              ? '한 끼 남기기'
              : '오늘의 한 끼',
          style: type(
            17,
            color: photo == null ? Colors.white : ink,
            weight: FontWeight.w500,
          ),
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
  Widget mealSelector({bool dark = false}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ChoiceChip(
            label: Text(mealNames[i]),
            selected: meal == i,
            onSelected: busy ? null : (_) => setState(() => meal = i),
            showCheckmark: false,
            backgroundColor: dark ? const Color(0xff242b33) : Colors.white,
            selectedColor: dark ? const Color(0xff3e4650) : sky,
            side: BorderSide.none,
            labelStyle: type(
              13,
              color: dark
                  ? Colors.white
                  : meal == i
                  ? cherry
                  : muted,
            ),
          ),
        ),
    ],
  );
  Widget camera() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          children: [
            mealSelector(dark: true),
            const SizedBox(height: 20),
            Container(
              height: (constraints.maxHeight * .43).clamp(160.0, 350.0),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xff303943),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.camera,
                    size: 45,
                    color: Colors.white70,
                  ),
                  const SizedBox(height: 20),
                  Text('오늘의 한 끼를 담아주세요.', style: type(16, color: Colors.white)),
                  const SizedBox(height: 9),
                  Text(
                    '아래 촬영 버튼을 누르면 카메라가 열려요.',
                    style: type(12, color: Colors.white60),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  CupertinoIcons.lock_shield,
                  size: 15,
                  color: Color(0xffb6cbdc),
                ),
                const SizedBox(width: 7),
                Text(
                  '사진첩에는 저장하지 않아요',
                  style: type(12, color: const Color(0xffcfdeea)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('우리 식탁에만 남는 한 끼', style: type(11, color: Colors.white54)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: '기존 사진 고르기',
                  onPressed: busy ? null : () => pick(ImageSource.gallery),
                  icon: const Icon(
                    CupertinoIcons.photo,
                    color: Colors.white70,
                    size: 26,
                  ),
                ),
                Semantics(
                  label: '식사 사진 촬영',
                  button: true,
                  child: GestureDetector(
                    onTap: busy ? null : () => pick(ImageSource.camera),
                    child: Container(
                      width: 75,
                      height: 75,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: busy
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              '잘 차리지 않아도 괜찮아.\n네가 잘 먹고 있으면 됐어.',
              textAlign: TextAlign.center,
              style: type(12, color: Colors.white60, height: 1.9),
            ),
          ],
        ),
      ),
    ),
  );
  Widget compose() => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      8,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 1.25,
            child: Image.file(photo!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 18),
        mealSelector(),
        const SizedBox(height: 16),
        Text('한마디도 같이 보낼까?', style: type(14, weight: FontWeight.w500)),
        const SizedBox(height: 10),
        TextField(
          controller: caption,
          maxLength: 80,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '오늘은 뭐가 제일 맛있었어?',
            helperText: '한마디는 선택이에요.',
          ),
        ),
        const SizedBox(height: 19),
        Text('어느 식탁에 올릴까요?', style: type(14, weight: FontWeight.w500)),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final table in widget.store.tables)
              FilterChip(
                selected: recipients.contains(table.id),
                showCheckmark: true,
                label: Text('${table.name}${table.isCloud ? '' : ' · 이 기기'}'),
                labelStyle: type(
                  12,
                  color: recipients.contains(table.id) ? cherry : muted,
                ),
                selectedColor: const Color(0xfffbedf1),
                backgroundColor: soft,
                side: BorderSide.none,
                onSelected: busy
                    ? null
                    : (selected) => setState(() {
                        // Keep delivery atomic across destinations with the same storage type.
                        if (selected) {
                          recipients.removeWhere(
                            (id) => id.startsWith('local-') == table.isCloud,
                          );
                          recipients.add(table.id);
                        } else {
                          recipients.remove(table.id);
                        }
                      }),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.lock_shield, size: 14, color: muted),
            const SizedBox(width: 6),
            Text('사진첩에는 저장되지 않아요', style: type(11, color: muted)),
          ],
        ),
        const SizedBox(height: 14),
        PrimaryButton(
          recipients.any((id) => !id.startsWith('local-'))
              ? '${recipients.length}개의 식탁에 보내기'
              : '내 식탁에 한 끼 남기기',
          onPressed: recipients.isEmpty ? null : save,
          busy: busy,
        ),
        Center(
          child: TextButton(
            onPressed: busy ? null : () => setState(() => photo = null),
            child: Text('다시 찍을래', style: type(12, color: muted)),
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
