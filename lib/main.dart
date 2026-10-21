import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';
import 'cloud.dart';
import 'models.dart';
import 'nudges.dart';
import 'store.dart';
import 'compose.dart';
import 'settings.dart';
import 'post_card.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  try {
    await CloudApi.initialize();
    final preferences = await SharedPreferences.getInstance();
    final directory = await getApplicationSupportDirectory();
    final store = MealStore(preferences, directory);
    await store.load();
    runApp(MwomeogeoApp(store: store));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_circle, size: 36),
                    const SizedBox(height: 16),
                    const Text(
                      '기록을 안전하게 열지 못했어요.\n저장 공간을 확인한 뒤 다시 시도해 주세요.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: main, child: const Text('다시 시도')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MwomeogeoApp extends StatelessWidget {
  const MwomeogeoApp({super.key, required this.store});
  final MealStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '뭐먹어?',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: milk,
      colorScheme: ColorScheme.fromSeed(seedColor: cherry, surface: milk),
      textTheme: TextTheme(bodyMedium: type(14), bodyLarge: type(16)),
      dividerColor: line,
      dialogTheme: const DialogThemeData(
        backgroundColor: milk,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: milk,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: cherry),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: milk,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        floatingLabelStyle: type(13, color: cherry),
        labelStyle: type(13, color: muted),
        hintStyle: type(13, color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cherry),
        ),
      ),
    ),
    builder: (context, child) => Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: child!,
    ),
    home: HomeScreen(store: store),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});
  final MealStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  MealStore get s => widget.store;
  int page = 0;
  DateTime now = DateTime.now();
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool refreshing = false;
  final Set<int> nudging = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.nudges.onOpen = openNudge;
    if (s.cloud.configured) {
      unawaited(
        s.connect().catchError((Object error) {
          if (mounted) toast(context, '$error');
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.nudges.onOpen = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => now = DateTime.now());
      unawaited(s.nudges.restore(s.table?.id).catchError((Object _) {}));
    }
  }

  void openNudge(String id) {
    if (!mounted || !s.tables.any((table) => table.id == id)) return;
    s.selectTable(id);
    setState(() {
      page = 0;
      now = DateTime.now();
    });
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      await s.refresh();
      setState(() => now = DateTime.now());
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> capture({int? initialMeal}) async {
    if (s.demo) await s.setDemo(false);
    if (!mounted) return;
    if (s.table == null) {
      await openTables(context, s);
      return;
    }
    final hour = DateTime.now().hour;
    final suggestedMeal = hour < 11 ? 0 : (hour < 17 ? 1 : 2);
    final selected = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CaptureScreen(store: s, initialMeal: initialMeal ?? suggestedMeal),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        page = 0;
        now = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          color: cherry,
          child: CustomScrollView(
            key: ValueKey(page),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: header()),
              if (s.table == null)
                SliverFillRemaining(hasScrollBody: false, child: emptyTables())
              else if (page == 0)
                ...feed()
              else
                ...calendar(),
              if (s.table != null)
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: navigation(),
    ),
  );

  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 6, 16, 0),
    child: Row(
      children: [
        Semantics(
          header: true,
          child: Text(
            '뭐먹어?',
            style: type(24, weight: FontWeight.w700, spacing: -1.3),
          ),
        ),
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(left: 3, top: 12),
          decoration: const BoxDecoration(
            color: cherry,
            shape: BoxShape.circle,
          ),
        ),
        const Spacer(),
        if (refreshing)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        IconButton(
          tooltip: '내 정보와 식탁 관리',
          onPressed: () => openSettings(context, s),
          icon: Avatar(s.name, size: 34),
        ),
      ],
    ),
  );

  Widget groups() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Flexible(
            child: TextButton(
              onPressed: () => openTables(context, s),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 44),
                foregroundColor: ink,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      s.table!.name,
                      overflow: TextOverflow.ellipsis,
                      style: type(13, weight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(CupertinoIcons.chevron_down, size: 11),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${s.demo ? (s.tableId.endsWith('couple') ? 2 : 4) : s.table!.memberCount}명',
            style: type(11, color: muted),
          ),
          const Spacer(),
          IconButton(
            tooltip: '식탁 만들기 또는 참여',
            onPressed: () => openTables(context, s),
            icon: const Icon(CupertinoIcons.plus, size: 16, color: muted),
          ),
        ],
      ),
    ),
  );

  Widget emptyTables() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('식탁 0개', style: type(12, color: muted)),
        ),
        const SizedBox(height: 22),
        Image.asset(
          'assets/illustrations/first-table.png',
          height: (MediaQuery.sizeOf(context).width * .50).clamp(130.0, 200.0),
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 20),
        Text(
          '우리의 첫 식탁을\n만들어요',
          textAlign: TextAlign.center,
          style: type(27, weight: FontWeight.w600, spacing: -1, height: 1.35),
        ),
        const SizedBox(height: 15),
        Text(
          '한 끼 사진으로 나누는\n가까운 사람들의 안부.',
          textAlign: TextAlign.center,
          style: type(14, color: muted, height: 1.7),
        ),
        const SizedBox(height: 30),
        PrimaryButton('첫 식탁 만들기', onPressed: () => openTables(context, s)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => openTables(context, s, join: true),
          child: Text('초대 코드로 참여하기', style: type(14, color: cherry)),
        ),
        const SizedBox(height: 14),
        Text('회원가입 없이 시작해요.', style: type(11, color: muted)),
        if (s.syncError != null) ...[
          const SizedBox(height: 18),
          Text(s.syncError!, style: type(12, color: cherry)),
        ],
      ],
    ),
  );

  List<Widget> feed() {
    final posts = s.postsOn(now);
    final meals = [
      for (var i = 0; i < 3; i++) posts.where((p) => p.meal == i).toList(),
    ];
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            groups(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 4),
              child: Row(
                children: [
                  Text(dayLabel(now), style: type(12, color: muted)),
                  const Spacer(),
                  IconButton(
                    tooltip: '달력 보기',
                    onPressed: () => setState(() => page = 1),
                    icon: const Icon(
                      CupertinoIcons.calendar,
                      size: 18,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Text(
                '오늘도, 잘 먹었어?',
                style: type(
                  25,
                  weight: FontWeight.w600,
                  spacing: -1.1,
                  height: 1.35,
                ),
              ),
            ),
            if (s.syncError != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(s.syncError!, style: type(12, color: cherry)),
              ),
            if (!s.demo && s.table?.isCloud == false)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('이 기기에 보관 중', style: type(10, color: muted)),
              ),
          ],
        ),
      ),
      for (var i = 0; i < 3; i++) ...mealSection(i, meals[i]),
    ];
  }

  List<Widget> mealSection(int meal, List<MealPost> posts) {
    if (posts.isEmpty) return [SliverToBoxAdapter(child: emptyMeal(meal))];
    final paired =
        posts.length > 1 &&
        MediaQuery.sizeOf(context).width >= 360 &&
        MediaQuery.textScalerOf(context).scale(1) < 1.3;
    Widget card(int index) => PostCard(
      key: ValueKey('post-${posts[index].id}'),
      post: posts[index],
      store: s,
      compact: true,
      tile: paired,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          key: ValueKey('meal-section-$meal'),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Icon(mealIcons[meal], size: 20, color: cherry),
              const SizedBox(width: 9),
              Text(mealNames[meal], style: type(14, weight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${posts.length}', style: type(11, color: muted)),
              const Spacer(),
              nudgeButton(meal),
              TextButton(
                onPressed: () => capture(initialMeal: meal),
                child: Text(
                  '+ 남기기',
                  semanticsLabel: '${mealNames[meal]} 남기기',
                  style: type(12, color: cherry),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverList.builder(
        itemCount: paired ? (posts.length + 1) ~/ 2 : posts.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: paired
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: card(index * 2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: index * 2 + 1 < posts.length
                          ? card(index * 2 + 1)
                          : const SizedBox.shrink(),
                    ),
                  ],
                )
              : card(index),
        ),
      ),
    ];
  }

  Widget emptyMeal(int meal) => Padding(
    key: ValueKey('meal-section-$meal'),
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(mealIcons[meal], size: 20, color: cherry),
          const SizedBox(width: 9),
          Text(mealNames[meal], style: type(14, weight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '아직 남긴 ${mealNames[meal]} 사진이 없어요.',
              style: type(11, color: muted),
            ),
          ),
          nudgeButton(meal),
          TextButton(
            onPressed: () => capture(initialMeal: meal),
            child: Text(
              '+ 남기기',
              semanticsLabel: '${mealNames[meal]} 남기기',
              style: type(12, color: cherry),
            ),
          ),
        ],
      ),
    ),
  );

  Widget nudgeButton(int meal) => IconButton(
    tooltip: '${mealNames[meal]} 알림 보내기',
    onPressed: nudging.contains(meal) ? null : () => nudgeMeal(meal),
    icon: nudging.contains(meal)
        ? const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        : const Icon(CupertinoIcons.bell, size: 17, color: cherry),
  );

  Future<void> nudgeMeal(int meal) async {
    final table = s.table;
    if (table == null || nudging.contains(meal)) return;
    if (s.demo || !table.isCloud || !s.nudges.configured) {
      await openMealNudge(context, s, meal);
      return;
    }
    setState(() => nudging.add(meal));
    try {
      await s.nudges.send(table.id, meal, requestId: newId());
      if (mounted) {
        toast(context, '${table.name}에 “${mealNudgeText(meal)}” 알림을 보냈어요.');
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => nudging.remove(meal));
    }
  }

  Widget navigation() => Container(
    decoration: const BoxDecoration(
      color: milk,
      border: Border(top: BorderSide(color: line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        child: Row(
          children: [
            Expanded(
              child: navItem(
                CupertinoIcons.house,
                '식탁',
                page == 0,
                () => setState(() => page = 0),
              ),
            ),
            Expanded(
              child: Semantics(
                button: true,
                label: '한 끼 남기기',
                child: InkWell(
                  onTap: capture,
                  borderRadius: BorderRadius.circular(22),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: cherry,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.camera,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text('남기기', style: type(10, color: muted)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: navItem(
                CupertinoIcons.doc_plaintext,
                '기록',
                page == 1,
                () => setState(() => page = 1),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget navItem(
    IconData icon,
    String label,
    bool active,
    VoidCallback action,
  ) => Semantics(
    selected: active,
    button: true,
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: active ? cherry : muted),
            const SizedBox(height: 5),
            Text(label, style: type(10, color: active ? cherry : muted)),
            const SizedBox(height: 3),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: active ? cherry : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> calendar() {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = month.weekday % 7;
    final monthRecords = s.allPosts
        .where(
          (p) =>
              p.tableIds.contains(s.tableId) &&
              p.date.year == month.year &&
              p.date.month == month.month &&
              !p.isDemo,
        )
        .toList();
    final recordedDays = monthRecords.map((p) => p.date.day).toSet().length;
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            groups(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('하루 세 번, 차곡차곡', style: type(12, color: muted)),
                  const SizedBox(height: 12),
                  Text(
                    '함께 쌓이는,',
                    style: type(
                      25,
                      weight: FontWeight.w500,
                      spacing: -1.5,
                      height: 1.4,
                    ),
                  ),
                  Text(
                    '우리의 하루.',
                    style: type(
                      25,
                      color: cherry,
                      weight: FontWeight.w500,
                      spacing: -1.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 10),
              child: Row(
                children: [
                  Text(
                    '${month.year}년 ${month.month}월',
                    style: type(17, weight: FontWeight.w500),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '이전 달',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const Icon(CupertinoIcons.chevron_left, size: 18),
                  ),
                  IconButton(
                    tooltip: '다음 달',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const Icon(CupertinoIcons.chevron_right, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (final weekday in ['일', '월', '화', '수', '목', '금', '토'])
                    Expanded(
                      child: Center(
                        child: Text(weekday, style: type(11, color: muted)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index < offset) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, index - offset + 1);
            final records = s.postsOn(date);
            final today = sameDay(date, now);
            return InkWell(
              onTap: () => showDay(date),
              borderRadius: BorderRadius.circular(10),
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(11),
                        border: today
                            ? Border.all(color: cherry, width: 1.5)
                            : null,
                      ),
                      child: records.isEmpty
                          ? const Center(
                              child: Icon(
                                CupertinoIcons.circle_fill,
                                size: 3,
                                color: Color(0xffb9c8d2),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: MealPhoto(
                                records.first,
                                s,
                                edition: false,
                              ),
                            ),
                    ),
                  ),
                  Text(
                    '${date.day}',
                    style: type(10, color: today ? cherry : muted),
                  ),
                ],
              ),
            );
          }, childCount: days + offset),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: .72,
            crossAxisSpacing: 3,
            mainAxisSpacing: 8,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: sky,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.tray,
                  size: 27,
                  color: Color(0xff6b899f),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '이달엔 $recordedDays일, 안부가 쌓였어요.',
                        style: type(
                          13,
                          weight: FontWeight.w500,
                          color: const Color(0xff526c80),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '사진을 누르면 그날의 밥상을 볼 수 있어요.',
                        style: type(11, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (s.demo)
        SliverToBoxAdapter(
          child: Center(
            child: Text(
              '오늘의 예시 사진만 미리보기에 표시돼요.',
              style: type(10, color: muted),
            ),
          ),
        ),
    ];
  }

  void showDay(DateTime date) {
    final posts = s.postsOn(date);
    showAppSheet(
      context,
      title: '${date.month}월 ${date.day}일의 밥상',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            posts.isEmpty ? '이날은 남긴 식사 사진이 없어요.' : '오늘의 우리, 이렇게 챙겨 먹었어요.',
            style: type(13, color: muted),
          ),
          const SizedBox(height: 20),
          for (final post in posts) PostCard(post: post, store: s),
          if (posts.isEmpty && sameDay(date, now))
            PrimaryButton(
              '오늘 한 끼 남기기',
              onPressed: () {
                Navigator.pop(context);
                capture();
              },
            ),
        ],
      ),
    );
  }
}
