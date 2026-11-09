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
    ZStack(alignment: .bottomTrailing) {
      Image("RiceFriends")
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 20)
      Image("MealCamera")
        .resizable()
        .scaledToFit()
        .frame(width: 32, height: 32)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("한 끼 바로 촬영")
    .containerBackground(Color(red: 1, green: 0.906, blue: 0.855), for: .widget)
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
