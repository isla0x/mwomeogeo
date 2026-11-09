import 'dart:math';

String newId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

const mealNames = ['아침', '점심', '저녁'];
const mealEditions = ['BREAKFAST', 'LUNCH', 'DINNER'];
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String dayLabel(DateTime d) =>
    '${d.month}월 ${d.day}일 ${['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1]}요일';
String timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class DiningTable {
  const DiningTable(
    this.id,
    this.name, {
    this.memberCount = 1,
    this.inviteCode,
    this.memberIds = const [],
  });
  final String id;
  final String name;
  final int memberCount;
  final String? inviteCode;
  final List<String> memberIds;
  bool get isCloud => !id.startsWith('local-');
}

class MealComment {
  MealComment(this.name, this.text);
  final String name;
  final String text;
  Map<String, dynamic> toJson() => {'name': name, 'text': text};
}

const riceStickerNames = ['냠냠', '배불러', '하트', '배달', '함께'];

class RiceSticker {
  const RiceSticker(
    this.userId,
    this.name,
    this.variant,
    this.x,
    this.y,
    this.scale,
  );
  final String userId, name;
  final int variant;
  final double x, y, scale;
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'variant': variant,
    'x': x,
    'y': y,
    'scale': scale,
  };
  factory RiceSticker.fromJson(Map<String, dynamic> j) => RiceSticker(
    j['userId'] as String,
    j['name'] as String,
    j['variant'] as int,
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    (j['scale'] as num).toDouble(),
  );
}

class MealPost {
  MealPost({
    required this.id,
    required this.author,
    required this.photo,
    required this.meal,
    required this.date,
    required this.tableIds,
    this.caption = '',
    this.isDemo = false,
    this.authorId,
    Set<String>? reactions,
    List<MealComment>? comments,
    List<RiceSticker>? stickers,
  }) : reactions = reactions ?? {},
       comments = comments ?? [],
       stickers = stickers ?? [];
  final String id;
  final String author;
  final String? authorId;
  final String photo;
  final int meal;
  final DateTime date;
  final List<String> tableIds;
  final String caption;
  final bool isDemo;
  final Set<String> reactions;
  final List<MealComment> comments;
  final List<RiceSticker> stickers;
  bool get isCloud => photo.startsWith('cloud:');
  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author,
    'photo': photo,
    'meal': meal,
    'date': date.toIso8601String(),
    'tables': tableIds,
    'caption': caption,
    'reactions': reactions.toList(),
    'stickers': stickers.map((s) => s.toJson()).toList(),
    'comments': comments.map((c) => c.toJson()).toList(),
  };
  factory MealPost.fromJson(Map<String, dynamic> j) => MealPost(
    stickers: (j['stickers'] as List? ?? [])
        .map((s) => RiceSticker.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
    id: j['id'] as String,
    author: j['author'] as String,
    photo: j['photo'] as String,
    meal: j['meal'] as int,
    date: DateTime.parse(j['date'] as String),
    tableIds: List<String>.from(j['tables'] as List),
    caption: j['caption'] as String,
    reactions: Set<String>.from(j['reactions'] as List? ?? []),
    comments: (j['comments'] as List? ?? [])
        .map((c) => MealComment(c['name'] as String, c['text'] as String))
        .toList(),
  );
}

List<MealPost> demoPosts(DateTime now) => [
  for (final row in [
    ['couple', 0, '지우', 'toast', '늦잠 자도 아침은 챙겨 먹기 🍳', 8, 24],
    ['couple', 1, '지우', 'bowl', '오늘은 조금 가볍게. 너도 잘 챙겨 먹어.', 12, 26],
    ['family', 0, '엄마', 'breakfast', '다들 아침 거르지 말고 챙겨 먹어 ☀️', 7, 40],
    ['family', 1, '엄마', 'pasta', '오늘은 아빠랑 오랜만에 파스타 🍝', 12, 10],
  ])
    MealPost(
      id: 'demo-${row[0]}-${row[1]}',
      author: row[2] as String,
      photo: 'asset:${row[3]}',
      meal: row[1] as int,
      date: DateTime(
        now.year,
        now.month,
        now.day,
        row[5] as int,
        row[6] as int,
      ),
      tableIds: ['local-${row[0]}'],
      caption: row[4] as String,
      isDemo: true,
    ),
];

// Membership order, never upload order, determines each person's seat.
String mealAuthorKey(MealPost post) =>
    post.isCloud ? (post.authorId ?? post.author) : post.author;
List<List<MealPost?>> fixedMealRows(List<MealPost> posts, List<String> seats) {
  final grouped = <String, List<MealPost>>{};
  for (final post in posts) {
    grouped.putIfAbsent(mealAuthorKey(post), () => []).add(post);
  }
  final order = [...seats.toSet()];
  order.addAll(
    grouped.keys.where((key) => !order.contains(key)).toList()..sort(),
  );
  for (final values in grouped.values) {
    values.sort((a, b) => b.date.compareTo(a.date));
  }
  final rows = <List<MealPost?>>[];
  for (var seat = 0; seat < order.length; seat += 2) {
    final left = grouped[order[seat]] ?? <MealPost>[];
    final right = seat + 1 < order.length
        ? grouped[order[seat + 1]] ?? <MealPost>[]
        : <MealPost>[];
    final count = left.length > right.length ? left.length : right.length;
    for (var row = 0; row < count; row++) {
      rows.add([
        row < left.length ? left[row] : null,
        row < right.length ? right[row] : null,
      ]);
    }
  }
  return rows;
}

// Exact inclusive time windows requested by the user; gaps require a choice.
int? mealAtCaptureTime(DateTime time) {
  final minute = time.hour * 60 + time.minute;
  if (minute >= 5 * 60 && minute <= 10 * 60) return 0;
  if (minute >= 11 * 60 && minute <= 16 * 60) return 1;
  if (minute >= 17 * 60 && minute <= 22 * 60) return 2;
  return null;
}

// Calendar day and upload time are distinct: a late entry keeps its chosen day.
DateTime mealRecordTime(DateTime? day, DateTime uploadedAt) {
  if (day == null) return uploadedAt;
  final selected = DateTime(day.year, day.month, day.day);
  final today = DateTime(uploadedAt.year, uploadedAt.month, uploadedAt.day);
  if (selected.year < 2000 || selected.isAfter(today)) {
    throw ArgumentError('오늘 또는 지난 날짜를 골라 주세요.');
  }
  return DateTime(
    day.year,
    day.month,
    day.day,
    uploadedAt.hour,
    uploadedAt.minute,
    uploadedAt.second,
    uploadedAt.millisecond,
    uploadedAt.microsecond,
  );
}
