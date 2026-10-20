import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';
import 'cloud.dart';
import 'models.dart';
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
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: cherry,
        surface: Colors.white,
      ),
      textTheme: TextTheme(bodyMedium: type(14), bodyLarge: type(16)),
      dividerColor: line,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: soft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cherry),
        ),
      ),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => now = DateTime.now());
    }
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
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: refresh,
              color: cherry,
              child: CustomScrollView(
                key: ValueKey(page),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: header()),
                  if (s.table == null)
                    SliverToBoxAdapter(child: emptyTables())
                  else if (page == 0)
                    ...feed()
                  else
                    ...calendar(),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 116 + MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              left: 24,
              right: 24,
              child: navigation(),
            ),
          ],
        ),
      ),
    ),
  );
  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 16, 10),
    child: Row(
      children: [
        Semantics(
          header: true,
          child: Text(
            '뭐먹어?',
            style: type(27, weight: FontWeight.w700, spacing: -1.8),
          ),
        ),
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(left: 4, top: 14),
          decoration: const BoxDecoration(
            color: cherry,
            shape: BoxShape.circle,
          ),
        ),
        const Spacer(),
        if (refreshing)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        IconButton(
          tooltip: '식탁 소식',
          onPressed: () => notifications(context, s),
          icon: const Icon(CupertinoIcons.bell, size: 21),
        ),
        IconButton(
          tooltip: '내 정보와 식탁 관리',
          onPressed: () => openSettings(context, s),
          icon: Avatar(s.name, size: 30),
        ),
      ],
    ),
  );
  Widget groups() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final g in s.tables)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: s.tableId == g.id
                            ? sky
                            : Colors.transparent,
                        foregroundColor: s.tableId == g.id
                            ? const Color(0xff405d73)
                            : muted,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      onPressed: () => s.selectTable(g.id),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            g.name,
                            style: type(
                              12,
                              color: s.tableId == g.id
                                  ? const Color(0xff405d73)
                                  : muted,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            '${s.demo && !g.isCloud ? (g.id.endsWith('couple') ? 2 : 4) : g.memberCount}'
                                .padLeft(2, '0'),
                            style: type(10, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '식탁 만들기 또는 참여',
                  onPressed: () => openTables(context, s),
                  icon: const Icon(CupertinoIcons.plus, size: 16),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        const Icon(CupertinoIcons.lock_shield, size: 12, color: muted),
        const SizedBox(width: 4),
        Text('우리끼리만', style: type(10, color: muted)),
      ],
    ),
  );
  Widget emptyTables() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '아직 함께하는 식탁이 없어요.',
          style: type(25, weight: FontWeight.w500, height: 1.4),
        ),
        const SizedBox(height: 14),
        Text(
          '식탁 0개 · 가까운 사람들과 첫 식탁을 만들어 보세요.\n이미 초대받았다면 코드로 참여할 수 있어요.',
          style: type(13, color: muted, height: 1.8),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          '식탁 만들기',
          onPressed: () => openTables(context, s),
          icon: CupertinoIcons.plus,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => openTables(context, s),
          child: const Text('초대 코드로 참여'),
        ),
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
      for (var i = 0; i < 3; i++)
        posts.where((post) => post.meal == i).toList(),
    ];
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.syncError != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(s.syncError!, style: type(11, color: cherry)),
              ),
            groups(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dayLabel(now)}  ─  하루의 기록',
                    style: type(11, color: muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    MediaQuery.sizeOf(context).width < 350 ||
                            MediaQuery.textScalerOf(context).scale(1) > 1.2
                        ? '오늘도\n잘 먹고 있어?'
                        : '오늘도 잘 먹고 있어?',
                    style: type(
                      30,
                      weight: FontWeight.w500,
                      spacing: -1.8,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text('한 끼 사진으로 나누는, 우리의 안부.', style: type(12, color: muted)),
                ],
              ),
            ),
            if (s.demo)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 20, 0),
                child: Row(
                  children: [
                    Text('디자인 미리보기 · 예시 식탁', style: type(10, color: muted)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => s.setDemo(false),
                      child: Text('내 기록 시작', style: type(11, color: cherry)),
                    ),
                  ],
                ),
              ),
            if (!s.demo && s.table?.isCloud == false)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                child: Text(
                  '이 기기에 보관 중 · 함께 보려면 공유 식탁을 연결해 주세요.',
                  style: type(10, color: muted),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        SliverToBoxAdapter(
          child: Padding(
            key: ValueKey('meal-section-$i'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Row(
              children: [
                Icon(mealIcons[i], size: 18, color: cherry),
                const SizedBox(width: 8),
                Text(mealNames[i], style: type(15, weight: FontWeight.w500)),
                const SizedBox(width: 8),
                Text('${meals[i].length}', style: type(11, color: muted)),
                const Spacer(),
                TextButton(
                  onPressed: () => capture(initialMeal: i),
                  child: Text(
                    '${mealNames[i]} 남기기',
                    style: type(11, color: cherry),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (meals[i].isEmpty)
          SliverToBoxAdapter(child: emptyMeal(i))
        else
          SliverList.builder(
            itemCount: meals[i].length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: PostCard(post: meals[i][index], store: s),
            ),
          ),
      ],
      if (posts.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: capture,
              child: Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '오늘의 한 끼도 놓아둘까요?',
                            style: type(
                              13,
                              color: const Color(0xff4f687c),
                              weight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '사진 한 장으로, 오늘의 안부를.',
                            style: type(11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 17,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget emptyMeal(int meal) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '아직 남긴 ${mealNames[meal]} 사진이 없어요.',
        style: type(12, color: muted),
      ),
    ),
  );
  Widget navigation() => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .98),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: line),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .05),
          blurRadius: 24,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: navItem(
            CupertinoIcons.tray,
            '우리 식탁',
            page == 0,
            () => setState(() => page = 0),
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: FilledButton.icon(
              onPressed: capture,
              icon: const Icon(CupertinoIcons.camera, size: 19),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('한 끼 남기기'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cherry,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 47),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: type(12, weight: FontWeight.w500),
              ),
            ),
          ),
        ),
        Expanded(
          child: navItem(
            CupertinoIcons.calendar,
            '모아보기',
            page == 1,
            () => setState(() => page = 1),
          ),
        ),
      ],
    ),
  );
  Widget navItem(
    IconData icon,
    String label,
    bool active,
    VoidCallback action,
  ) => Semantics(
    selected: active,
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 51,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: active ? cherry : muted),
            const SizedBox(height: 3),
            Text(label, style: type(10, color: active ? cherry : muted)),
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
                  Text('하루 세 번, 차곡차곡', style: type(11, color: muted)),
                  const SizedBox(height: 12),
                  Text(
                    '함께 쌓이는,',
                    style: type(
                      29,
                      weight: FontWeight.w500,
                      spacing: -1.5,
                      height: 1.4,
                    ),
                  ),
                  Text(
                    '우리의 하루.',
                    style: type(
                      29,
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
