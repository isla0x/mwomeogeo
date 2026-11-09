import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design.dart';
import 'camera_header.dart';
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
                    const AppIcon(
                      CupertinoIcons.exclamationmark_circle,
                      size: 36,
                    ),
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
      fontFamily: 'NanumSquareRound',
      fontFamilyFallback: const ['Pretendard'],
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
        style: TextButton.styleFrom(
          foregroundColor: cherry,
          textStyle: type(14, weight: FontWeight.w500),
        ),
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
    navigatorObservers: [mealCameraRoutes],
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
  final cameraKey = GlobalKey<MealCameraHeaderState>();
  DateTime? selectedDay;
  final Set<int> nudging = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.nudges.onOpen = openNudge;
    quickCapture.setMethodCallHandler((call) async {
      if (call.method == 'capture') await takeQuickCapture();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => takeQuickCapture());
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
    quickCapture.setMethodCallHandler(null);
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

  static const quickCapture = MethodChannel('com.chaen.mwomeogeo/capture');
  bool capturing = false;
  Future<void> takeQuickCapture() async {
    try {
      final pending = await quickCapture.invokeMethod<bool>('takeCapture');
      if (pending == true && mounted) await capture(openCamera: true);
    } on MissingPluginException {
      /* Unit tests and unsupported platforms. */
    }
  }

  Future<void> capture({
    int? initialMeal,
    bool openCamera = false,
    DateTime? recordedDate,
    File? initialPhoto,
    bool openGallery = false,
  }) async {
    if (capturing) return;
    capturing = true;
    if (mounted) setState(() {});
    await cameraKey.currentState?.pause();
    try {
      if (s.demo) await s.setDemo(false);
      if (openCamera && s.cloud.configured) {
        try {
          await s.connect();
        } catch (_) {}
      }
      if (!mounted) return;
      if (s.table == null) {
        await openTables(context, s);
        if (!openCamera || !mounted || s.table == null) return;
      }
      final suggestedMeal = mealAtCaptureTime(DateTime.now()) ?? 0;
      final selected = await Navigator.push<int>(
        context,
        MaterialPageRoute(
          builder: (_) => CaptureScreen(
            store: s,
            initialMeal: initialMeal ?? suggestedMeal,
            openCamera: openCamera,
            recordedDate: recordedDate,
            initialPhoto: initialPhoto,
            openGallery: openGallery,
          ),
        ),
      );
      if (selected != null && mounted) {
        setState(() {
          page = recordedDate == null ? 0 : 1;
          if (recordedDate != null) {
            month = DateTime(recordedDate.year, recordedDate.month);
          }
          now = DateTime.now();
        });
      }
    } finally {
      capturing = false;
      if (mounted) {
        setState(() {});
        if (page == 0) unawaited(cameraKey.currentState?.resume());
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            header(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                color: cherry,
                child: CustomScrollView(
                  key: ValueKey(page),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (page == 2)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                          child: SettingsContent(store: s),
                        ),
                      )
                    else if (s.table == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: emptyTables(),
                      )
                    else if (page == 0) ...[
                      SliverToBoxAdapter(
                        child: MealCameraHeader(
                          key: cameraKey,
                          demo: s.demo,
                          active: !capturing,
                          header: const SizedBox.shrink(),
                          onPhoto: (file) => capture(initialPhoto: file),
                          onCamera: () => capture(openCamera: true),
                          onGallery: () => capture(openGallery: true),
                        ),
                      ),
                      ...feed(),
                    ] else
                      ...calendar(),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: navigation(),
    ),
  );

  Widget header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    child: Row(
      children: [
        Expanded(
          flex: 4,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => openTables(context, s),
              style: TextButton.styleFrom(
                backgroundColor: soft,
                foregroundColor: ink,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 44),
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CuteIcon(MealGlyph.rooms, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      s.table?.name ?? '식탁 선택',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: type(12, weight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const AppIcon(CupertinoIcons.chevron_down, size: 10),
                ],
              ),
            ),
          ),
        ),
        const Spacer(flex: 3),
        const SizedBox(width: 8),
        TextButton(
          onPressed: capturing ? null : () => capture(),
          style: TextButton.styleFrom(
            backgroundColor: soft,
            foregroundColor: ink,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CuteIcon(MealGlyph.camera, size: 18),
              const SizedBox(width: 6),
              Text('올리기', style: type(12, weight: FontWeight.w500)),
            ],
          ),
        ),
      ],
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
        Container(
          width: 144,
          height: 144,
          decoration: const BoxDecoration(color: soft, shape: BoxShape.circle),
          child: const Center(child: CuteIcon(MealGlyph.rooms, size: 82)),
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
    return [
      SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: const BoxDecoration(
            color: milk,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: peach,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 7,
                      children: [
                        Text(
                          '오늘의 식탁',
                          style: type(
                            21,
                            weight: FontWeight.w700,
                            spacing: -.7,
                          ),
                        ),
                        const CuteIcon(MealGlyph.rooms, size: 32),
                      ],
                    ),
                  ),
                  Text(
                    '${now.month}월 ${now.day}일',
                    style: type(12, color: muted),
                  ),
                ],
              ),
              if (s.syncError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(s.syncError!, style: type(12, color: cherry)),
                ),
              if (!s.demo && s.table?.isCloud == false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('이 기기에 보관 중', style: type(11, color: muted)),
                ),
            ],
          ),
        ),
      ),
      for (var i = 0; i < 3; i++)
        ...mealSection(i, posts.where((p) => p.meal == i).toList()),
    ];
  }

  List<Widget> mealSection(
    int meal,
    List<MealPost> posts, {
    DateTime? date,
    VoidCallback? onAdd,
  }) {
    final inset = date == null ? 20.0 : 0.0;
    if (posts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: emptyMeal(meal, date: date, onAdd: onAdd),
        ),
      ];
    }
    final rows = s.mealRows(posts);
    final ordered = rows.expand((row) => row).whereType<MealPost>().toList();
    final paired =
        (s.demo || posts.length > 1 || s.table!.memberIds.length > 1) &&
        MediaQuery.sizeOf(context).width >= 360 &&
        MediaQuery.textScalerOf(context).scale(1) < 1.3;
    Widget card(MealPost post) => PostCard(
      key: ValueKey('post-${post.id}'),
      post: post,
      store: s,
      compact: true,
      tile: paired,
    );
    return [
      SliverToBoxAdapter(
        child: Padding(
          key: ValueKey('meal-section-$meal'),
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Row(
            children: [
              AppIcon(mealIcons[meal], size: 20, color: cherry),
              const SizedBox(width: 9),
              Text(mealNames[meal], style: type(15, weight: FontWeight.w500)),
              const SizedBox(width: 8),
              Text('${posts.length}', style: type(11, color: muted)),
              const Spacer(),

              TextButton(
                onPressed: date != null
                    ? onAdd
                    : () => capture(initialMeal: meal),
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
        itemCount: paired ? rows.length : ordered.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.fromLTRB(inset, 0, inset, 10),
          child: paired
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: rows[index][0] == null
                          ? missingPartner(
                              rows[index][1],
                              meal,
                              date: date,
                              onAdd: onAdd,
                            )
                          : card(rows[index][0]!),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: rows[index][1] != null
                          ? card(rows[index][1]!)
                          : missingPartner(
                              rows[index][0],
                              meal,
                              date: date,
                              onAdd: onAdd,
                            ),
                    ),
                  ],
                )
              : card(ordered[index]),
        ),
      ),
    ];
  }

  Widget emptyMeal(int meal, {DateTime? date, VoidCallback? onAdd}) => Padding(
    key: ValueKey('meal-section-$meal'),
    padding: EdgeInsets.fromLTRB(
      date == null ? 20 : 0,
      6,
      date == null ? 20 : 0,
      18,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(mealIcons[meal], size: 20),
            const SizedBox(width: 8),
            Text(mealNames[meal], style: type(15, weight: FontWeight.w500)),
            const Spacer(),

            TextButton(
              onPressed: date != null
                  ? onAdd
                  : () => capture(initialMeal: meal),
              child: Text(
                '+ 남기기',
                semanticsLabel: '${mealNames[meal]} 남기기',
                style: type(12, color: cherry),
              ),
            ),
          ],
        ),
        Text(
          '아직 남긴 ${mealNames[meal]} 사진이 없어요.',
          style: type(11, color: muted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var seat = 0; seat < 2; seat++) ...[
              if (seat > 0) const SizedBox(width: 12),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.55,
                  child: Material(
                    color: soft,
                    borderRadius: BorderRadius.circular(17),
                    child: InkWell(
                      onTap: date != null
                          ? onAdd
                          : () => capture(initialMeal: meal),
                      borderRadius: BorderRadius.circular(17),
                      child: Center(
                        child:
                            seat < (s.table?.memberIds.length ?? 0) &&
                                s.table!.memberIds[seat] != s.cloud.userId
                            ? missingSeat(
                                s.table!.memberIds[seat],
                                meal,
                                date: date,
                              )
                            : const CuteIcon(MealGlyph.addPhoto, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget missingPartner(
    MealPost? other,
    int meal, {
    DateTime? date,
    VoidCallback? onAdd,
  }) {
    final members = s.table?.memberIds ?? <String>[];
    final index = members.indexOf(other?.authorId ?? '');
    final seat = index < 0 ? -1 : index ^ 1;
    if (seat < 0 || seat >= members.length) return const SizedBox.shrink();
    final uid = members[seat];
    if (uid == s.cloud.userId) {
      return TextButton(
        onPressed: date == null ? () => capture(initialMeal: meal) : onAdd,
        child: const Text('+ 남기기'),
      );
    }
    return missingSeat(uid, meal, date: date);
  }

  Widget missingSeat(String uid, int meal, {DateTime? date}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('아직 사진이 없어요', style: type(11, color: muted)),
      IconButton(
        tooltip: '상대에게 밥풀 콕',
        onPressed:
            nudging.contains(meal) ||
                (date != null && !sameDay(date, DateTime.now()))
            ? null
            : () => nudgeMeal(meal, recipientId: uid),
        icon: const CuteIcon(MealGlyph.rooms, size: 25),
      ),
    ],
  );

  Future<void> nudgeMeal(int meal, {String? recipientId}) async {
    final table = s.table;
    if (table == null || nudging.contains(meal)) return;
    if (s.demo || !table.isCloud || !s.nudges.configured) {
      await openMealNudge(context, s, meal);
      return;
    }
    setState(() => nudging.add(meal));
    try {
      await s.nudges.send(
        table.id,
        meal,
        requestId: newId(),
        recipientId: recipientId,
      );
      if (mounted) {
        toast(context, '${table.name}에 “${mealNudgeText(meal)}” 알림을 보냈어요.');
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => nudging.remove(meal));
    }
  }

  Widget navigation() => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: milk,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: line, width: .6),
          ),
          child: Row(
            children: [
              for (final entry in const [
                (MealGlyph.table, '식탁'),
                (MealGlyph.calendar, '달력'),
                (MealGlyph.settings, '설정'),
              ])
                Expanded(
                  child: navItem(
                    entry.$1,
                    entry.$2,
                    page == ['식탁', '달력', '설정'].indexOf(entry.$2),
                    () => setState(
                      () => page = ['식탁', '달력', '설정'].indexOf(entry.$2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget navItem(
    MealGlyph icon,
    String label,
    bool active,
    VoidCallback action,
  ) => Semantics(
    selected: active,
    button: true,
    child: Material(
      color: active ? sky : Colors.transparent,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(26),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CuteIcon(icon, size: 19),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: type(
                    12,
                    color: active ? cherry : ink,
                    weight: active ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<Widget> calendar() {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = month.weekday % 7;
    final day =
        selectedDay != null &&
            selectedDay!.year == month.year &&
            selectedDay!.month == month.month
        ? selectedDay!
        : DateTime(
            month.year,
            month.month,
            sameDay(
                  DateTime(month.year, month.month),
                  DateTime(now.year, now.month),
                )
                ? now.day
                : 1,
          );
    final records = s.postsOn(day);
    final firstMeal = records.firstOrNull?.meal;
    final seats = firstMeal == null
        ? <MealPost?>[]
        : s.mealRows(records.where((p) => p.meal == firstMeal).toList()).first;
    final canAdd = !DateTime(
      day.year,
      day.month,
      day.day,
    ).isAfter(DateUtils.dateOnly(DateTime.now()));
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '이전 달',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                    icon: const AppIcon(CupertinoIcons.chevron_left, size: 16),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${month.month}월',
                          style: type(28, weight: FontWeight.w700),
                        ),
                        Text('${month.year}년', style: type(12, color: muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '다음 달',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                    icon: const AppIcon(CupertinoIcons.chevron_right, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  for (final weekday in ['일', '월', '화', '수', '목', '금', '토'])
                    Expanded(
                      child: Center(
                        child: Text(
                          weekday,
                          style: type(
                            12,
                            color: weekday == '일' ? cherry : muted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: .77,
            crossAxisSpacing: 2,
            mainAxisSpacing: 6,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index < offset) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, index - offset + 1);
            final posts = s.postsOn(date);
            final active = sameDay(date, day);
            final today = sameDay(date, now);
            return Semantics(
              button: true,
              selected: active,
              label: '${date.month}월 ${date.day}일, 사진 ${posts.length}장',
              child: InkWell(
                key: ValueKey(
                  'calendar-day-${date.year}-${date.month}-${date.day}',
                ),
                onTap: () {
                  setState(() => selectedDay = date);
                  showDay(date);
                },
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  children: [
                    Container(
                      alignment: Alignment.center,
                      constraints: const BoxConstraints(minHeight: 26),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: active ? peach : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: today && !active
                            ? Border.all(color: peach)
                            : null,
                      ),
                      child: Text(
                        '${date.day}',
                        style: type(
                          12,
                          color: active ? ink : muted,
                          weight: active ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: posts.isEmpty
                          ? const SizedBox()
                          : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: MealPhoto(
                                  posts.first,
                                  s,
                                  edition: false,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          }, childCount: days + offset),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${day.month}월 ${day.day}일의 식탁',
                style: type(20, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (seats.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < seats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => showDay(day),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                seats[i]?.author ?? '아직 남기지 않았어요',
                                style: type(12, color: muted),
                              ),
                              const SizedBox(height: 5),
                              AspectRatio(
                                aspectRatio: 1.1,
                                child: seats[i] == null
                                    ? const AppSurface(
                                        color: soft,
                                        child: Center(
                                          child: CuteIcon(
                                            MealGlyph.addPhoto,
                                            size: 24,
                                          ),
                                        ),
                                      )
                                    : MealPhoto(seats[i]!, s, edition: false),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              else
                AppSurface(
                  color: soft,
                  child: Row(
                    children: [
                      const CuteIcon(MealGlyph.album, size: 27),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '이날은 남긴 식사 사진이 없어요.',
                          style: type(12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              PrimaryButton(
                '이날 사진 추가',
                icon: CupertinoIcons.plus,
                onPressed: canAdd ? () => capture(recordedDate: day) : null,
              ),
              const SizedBox(height: 6),
              if (seats.isNotEmpty)
                Center(
                  child: TextButton(
                    onPressed: () => showDay(day),
                    child: Text('아침부터 저녁까지 보기', style: type(12, color: muted)),
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  Future<void> showDay(DateTime date) async {
    final today = DateTime.now();
    final canAdd = !DateTime(
      date.year,
      date.month,
      date.day,
    ).isAfter(DateTime(today.year, today.month, today.day));
    Future<void> add([int? meal]) async {
      Navigator.pop(context);
      await capture(initialMeal: meal, recordedDate: date);
      if (mounted && s.table != null) await showDay(date);
    }

    await showAppSheet(
      context,
      title: '${date.month}월 ${date.day}일의 밥상',
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final posts = s.postsOn(date);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                posts.isEmpty ? '이날은 남긴 식사 사진이 없어요.' : '이날의 우리, 이렇게 챙겨 먹었어요.',
                style: type(13, color: muted),
              ),
              if (canAdd)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: PrimaryButton(
                    '이날 사진 추가하기',
                    icon: CupertinoIcons.plus,
                    onPressed: () => add(),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CustomScrollView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  slivers: [
                    for (var meal = 0; meal < 3; meal++)
                      ...mealSection(
                        meal,
                        posts.where((p) => p.meal == meal).toList(),
                        date: date,
                        onAdd: canAdd ? () => add(meal) : null,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
