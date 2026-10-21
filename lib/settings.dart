import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cloud.dart';
import 'design.dart';
import 'models.dart';
import 'nudges.dart';
import 'store.dart';

Future<void> openSettings(
  BuildContext context,
  MealStore store,
) => showAppSheet(
  context,
  title: '나의 작은 식탁',
  child: ListenableBuilder(
    listenable: store,
    builder: (sheetContext, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Avatar(store.name, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.name, style: type(19, weight: FontWeight.w500)),
                  Text('오늘도 잘 챙겨 먹는 중', style: type(12, color: muted)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => editName(sheetContext, store),
              child: const Text('이름 변경'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => notifications(sheetContext, store),
          icon: const Icon(CupertinoIcons.bell, size: 18),
          label: const Text('식탁 소식'),
        ),
        ListenableBuilder(
          listenable: store.nudges,
          builder: (_, _) => AppOption(
            label: '식사 알림 받기',
            subtitle: store.nudges.busy
                ? '알림 연결 중이에요'
                : store.nudges.enabled
                ? '상대의 밥 안부를 알림으로 받아요'
                : '알림을 허용하면 상대의 밥 안부를 받아요',
            icon: store.nudges.enabled
                ? CupertinoIcons.bell_fill
                : CupertinoIcons.bell,
            selected: store.nudges.enabled,
            onTap: store.nudges.busy
                ? null
                : () async {
                    final table = store.table;
                    if (table == null || !table.isCloud || store.demo) {
                      toast(sheetContext, '함께 쓰는 식탁에서 알림을 받을 수 있어요.');
                      return;
                    }
                    try {
                      await store.nudges.setEnabled(
                        table.id,
                        !store.nudges.enabled,
                      );
                      if (sheetContext.mounted) {
                        toast(
                          sheetContext,
                          store.nudges.enabled ? '식사 알림을 켰어요.' : '식사 알림을 껐어요.',
                        );
                      }
                    } catch (e) {
                      if (sheetContext.mounted) toast(sheetContext, '$e');
                    }
                  },
          ),
        ),
        settingRow('사진첩에 자동 저장', '저장 안 함'),
        settingRow('현재 식탁', store.table?.name ?? '없음'),
        if (store.table != null)
          settingRow(
            '기록 보관',
            store.table!.isCloud ? '초대한 사람끼리만' : '이 기기 안에 보관',
          ),
        if (store.cloud.signedIn) settingRow('함께 쓰는 식탁', '이 기기와 연결됨'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '앱에서 찍은 사진은 내 사진첩에 쌓이지 않아요.\n앱을 삭제하면 이 기기에만 보관한 기록도 사라져요.',
            style: type(12, color: muted, height: 1.9),
          ),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          '함께 쓰는 식탁 관리',
          onPressed: () {
            Navigator.pop(sheetContext);
            openTables(context, store);
          },
          icon: CupertinoIcons.person_2,
        ),
        const SizedBox(height: 18),
        Text(
          '회원가입 없이 이 기기에서 이어 써요. 기기를 바꾸거나 앱 데이터를 초기화하면 새로 초대받아야 할 수 있어요.',
          style: type(11, color: muted, height: 1.8),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            '뭐먹어?  1.0.0 · CHERRY MILK',
            style: type(10, color: muted, spacing: 1),
          ),
        ),
      ],
    ),
  ),
);
Widget settingRow(String label, String value) => Container(
  padding: const EdgeInsets.symmetric(vertical: 16),
  decoration: const BoxDecoration(
    border: Border(bottom: BorderSide(color: line)),
  ),
  child: Row(
    children: [
      Expanded(child: Text(label, style: type(13))),
      Text(value, style: type(12, color: muted)),
    ],
  ),
);
Future<void> editName(BuildContext context, MealStore store) async {
  final controller = TextEditingController(text: store.name);
  final value = await showAppSheet<String>(
    context,
    title: '어떻게 불러드릴까요?',
    subtitle: '가까운 사람들이 알아볼 이름이면 좋아요.',
    child: Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            maxLength: 12,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (text) {
              if (text.trim().isNotEmpty) Navigator.pop(context, text.trim());
            },
            decoration: const InputDecoration(labelText: '식탁에서 쓸 이름'),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => PrimaryButton(
              '저장',
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.text.trim()),
            ),
          ),
        ],
      ),
    ),
  );
  if (value != null) {
    try {
      await store.setName(value);
    } catch (_) {
      if (context.mounted) toast(context, '이름을 저장하지 못했어요.');
    }
  }
  Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
}

Future<void> notifications(BuildContext context, MealStore store) async {
  final posts = store.allPosts
      .where((p) => p.tableIds.contains(store.tableId))
      .take(8)
      .toList();
  await showAppSheet(
    context,
    title: '식탁 소식',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('밥 한 끼에 담긴, 작은 마음들.', style: type(13, color: muted)),
        const SizedBox(height: 18),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              '아직 새로운 소식이 없어요.\n첫 한 끼를 가볍게 남겨볼까요?',
              style: type(14, color: muted),
            ),
          ),
        for (final post in posts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Avatar(post.author),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${post.author}의 ${mealNames[post.meal]}가 놓였어요.',
                        style: type(14),
                      ),
                      Text(
                        '${dayLabel(post.date)} ${timeLabel(post.date)}${post.isDemo ? ' · 예시 소식' : ''}',
                        style: type(11, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Text('앱 안에서 확인하는 식탁 소식이에요.', style: type(11, color: muted)),
      ],
    ),
  );
}

Future<void> openTables(
  BuildContext context,
  MealStore store, {
  bool join = false,
}) async {
  await showAppSheet(
    context,
    title: '함께 쓰는 식탁',
    child: _Tables(store: store, join: join),
  );
}

class _Tables extends StatefulWidget {
  const _Tables({required this.store, this.join = false});
  final MealStore store;
  final bool join;
  @override
  State<_Tables> createState() => _TablesState();
}

class _TablesState extends State<_Tables> {
  late final nickname = TextEditingController(text: widget.store.name);
  final name = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  String? error;
  bool joining = false;
  @override
  void initState() {
    super.initState();
    joining = widget.join && widget.store.cloud.configured;
    connect();
  }

  Future<void> connect() async {
    if (!widget.store.cloud.configured) return;
    setState(() => busy = true);
    try {
      await widget.store.connect();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    nickname.dispose();
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> perform(bool create) async {
    final value = (create ? name : code).text.trim();
    if (value.isEmpty || busy) return;
    if (nickname.text.trim().isEmpty) {
      setState(() => error = '식탁에서 쓸 이름을 적어 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!widget.store.cloud.configured) {
        if (!create) throw StateError('함께 쓰려면 Firebase 연결이 필요해요.');
        await widget.store.setName(nickname.text.trim());
        await widget.store.createLocalTable(value);
        if (mounted) Navigator.pop(context);
        return;
      }
      await widget.store.cloud.ensureIdentity(nickname.text.trim());
      await widget.store.setName(nickname.text.trim());
      final id = create
          ? await widget.store.cloud.createTable(value)
          : await widget.store.cloud.joinTable(value);
      await widget.store.refresh();
      widget.store.selectTable(id);
      await widget.store.setDemo(false);
      if (mounted) {
        name.clear();
        code.clear();
        toast(context, create ? '함께 쓸 식탁을 만들었어요.' : '식탁에 함께 앉았어요.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.store.cloud.configured
              ? '회원가입 없이, 이름과 초대 코드만으로.'
              : '이 기기에 보관할 식탁을 만들어요. 함께 공유하려면 Firebase 연결이 필요해요.',
          style: type(13, color: muted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: nickname,
          maxLength: 12,
          decoration: const InputDecoration(labelText: '식탁에서 쓸 이름'),
        ),
        const SizedBox(height: 16),
        if (error != null) ...[
          Text(error!, style: type(13, color: cherry)),
          TextButton(
            onPressed: busy ? null : connect,
            child: const Text('연결 다시 시도'),
          ),
          const SizedBox(height: 12),
        ],
        for (final table in widget.store.localTables)
          AppOption(
            label: table.name,
            subtitle: '이 기기에 보관',
            icon: CupertinoIcons.person_2,
            selected: table.id == widget.store.tableId,
            onTap: () {
              widget.store.selectTable(table.id);
              Navigator.pop(context);
            },
          ),
        for (final table in widget.store.remoteTables)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppOption(
                  label: table.name,
                  subtitle: '${table.memberCount}명 · 초대한 사람끼리만',
                  icon: CupertinoIcons.person_2,
                  selected: table.id == widget.store.tableId,
                  onTap: () {
                    widget.store.selectTable(table.id);
                    Navigator.pop(context);
                  },
                ),
                Text('초대 코드', style: type(11, color: muted)),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        table.inviteCode ?? '',
                        style: type(12, spacing: .5, color: cherry),
                      ),
                    ),
                    IconButton(
                      tooltip: '초대 코드 복사',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: table.inviteCode ?? ''),
                        );
                        if (context.mounted) toast(context, '초대 코드를 복사했어요.');
                      },
                      icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (widget.store.cloud.configured) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                for (final join in [false, true])
                  Expanded(
                    child: Semantics(
                      selected: joining == join,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                joining = join;
                                error = null;
                              }),
                        style: TextButton.styleFrom(
                          foregroundColor: joining == join ? ink : muted,
                          backgroundColor: joining == join
                              ? Colors.white
                              : Colors.transparent,
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          join ? '초대 코드로 참여' : '새 식탁 만들기',
                          style: type(12, weight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (!joining)
          TextField(
            controller: name,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '새 식탁 이름',
              hintText: '우리 둘, 가족 식탁…',
            ),
          )
        else
          TextField(
            controller: code,
            maxLength: 32,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: '받은 초대 코드'),
          ),
        const SizedBox(height: 8),
        PrimaryButton(
          joining ? '초대 코드로 함께하기' : '식탁 만들기',
          onPressed: () => perform(!joining),
          busy: busy,
          icon: joining ? CupertinoIcons.person_2 : CupertinoIcons.plus,
        ),
        const SizedBox(height: 16),
        Text(
          widget.store.cloud.configured
              ? '함께 쓰는 사진과 반응은 식탁을 보고 있을 때 자동으로 갱신돼요.'
              : CloudApi.initializationError ?? '사진은 이 기기의 앱 안에 보관돼요.',
          style: type(11, color: muted),
        ),
      ],
    ),
  );
}

Future<void> openMealNudge(
  BuildContext context,
  MealStore store,
  int meal,
) async {
  final table = store.table;
  if (table == null) return;
  await showAppSheet(
    context,
    title: '밥 안부 보내기',
    subtitle: '${table.name} · 나를 제외한 식탁 사람들에게',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.bell, size: 16, color: cherry),
                  const SizedBox(width: 8),
                  Text(
                    '뭐먹어?',
                    style: type(12, color: muted, weight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text('지금', style: type(10, color: muted)),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                mealNudgeText(meal),
                style: type(24, weight: FontWeight.w600, spacing: -.8),
              ),
              const SizedBox(height: 5),
              Text('한 끼 사진으로 안부를 전해줘.', style: type(13, color: muted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          store.demo
              ? '미리보기예요. 실제 알림은 보내지 않아요.'
              : !table.isCloud
              ? '초대 코드로 함께 쓰는 식탁에서 보낼 수 있어요.'
              : '식사 알림을 준비 중이에요. 다음 업데이트에서 만나요.',
          style: type(12, color: muted),
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          '${mealNames[meal]} 알림 보내기',
          icon: CupertinoIcons.paperplane,
          onPressed: null,
        ),
      ],
    ),
  );
}
