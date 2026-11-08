import SwiftUI
import WidgetKit

struct MealEntry: TimelineEntry { let date: Date }
struct MealProvider: TimelineProvider {
  func placeholder(in context: Context) -> MealEntry { MealEntry(date: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (MealEntry) -> Void) {
    completion(MealEntry(date: Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<MealEntry>) -> Void) {
    completion(Timeline(entries: [MealEntry(date: Date())], policy: .never))
  }
}
struct MealCaptureView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("뭐먹어?").font(.system(size: 15, weight: .bold))
        Spacer()
        Image(systemName: "camera.fill").font(.system(size: 24))
      }
      Spacer(minLength: 0)
      Text("지금 먹는 한 끼,").font(.system(size: 18, weight: .semibold))
      Text("사진으로 안부.").font(.system(size: 21, weight: .bold))
      Text("눌러서 바로 촬영").font(.system(size: 12))
    }
    .foregroundStyle(Color(red: 0.65, green: 0.24, blue: 0.31))
    .containerBackground(Color(red: 1, green: 0.965, blue: 0.906), for: .widget)
    .widgetURL(URL(string: "mwomeogeo://capture"))
  }
}
@main
struct MealCaptureWidget: Widget {
  let kind = "MealCaptureWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: MealProvider()) { _ in MealCaptureView() }
      .configurationDisplayName("한 끼 바로 촬영")
      .description("카메라를 바로 열고 우리 식탁에 사진을 올려요.")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}
