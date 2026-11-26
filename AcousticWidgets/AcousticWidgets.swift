import ActivityKit
import SwiftUI
import WidgetKit

/// AcousticWidgets 擴展（階段 6）：兩個桌面小組件＋節拍器
/// Live Activity 的渲染端。數據一律來自 App Group 快照
/// （SharedSnapshot，App 側組裝好本地化字串），擴展不持有
/// 字典、不讀 App 私有落盤；快照缺失時顯示出廠預設佔位。
///
/// 深連結（Info.plist 已登記 laurent-acoustic scheme）：
/// - 調音小組件 → laurent-acoustic://tuner
/// - 節拍器小組件 → laurent-acoustic://metronome；
///   START 钮 → laurent-acoustic://metronome/start（回 App
///   切節拍器頁並直接開始）。
@main
struct AcousticWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TunerWidget()
        MetronomeWidget()
        MetronomeLiveActivityWidget()
    }
}

// MARK: - 時間線（快照驅動：entry 恆為目前快照，policy .never
// ——App 側快照變更時以 WidgetCenter.reloadAllTimelines 主動
// 刷新，擴展不自行輪詢）

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context,
                     completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: SharedStore.read()))
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SharedStore.read())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

// MARK: - 調音小組件（快速視圖）

struct TunerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TunerWidget", provider: SnapshotProvider()) { entry in
            TunerWidgetView(entry: entry)
        }
        .configurationDisplayName("LAURENT 調音")
        .description("目前樂器與收藏一瞥即達，點按直達調音頁。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TunerWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "tuningfork")
                    .font(.system(size: 11, weight: .bold))
                Text(entry.snapshot.tunerLabel)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                Spacer()
                Text("LAURENT")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .opacity(0.55)
            }
            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

            Text(entry.snapshot.instrumentName)
                .font(.system(size: family == .systemMedium ? 19 : 17, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(entry.snapshot.instrumentKey) · \(entry.snapshot.a4Text)")
                .font(.system(size: 12, weight: .medium))
                .opacity(0.65)
                .lineLimit(1)

            if family == .systemMedium, !entry.snapshot.favoriteNames.isEmpty {
                HStack(spacing: 5) {
                    ForEach(entry.snapshot.favoriteNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(red: 0.07, green: 0.07, blue: 0.09)
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "laurent-acoustic://tuner"))
    }
}

// MARK: - 節拍器小組件（BPM 快速啟動）

struct MetronomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MetronomeWidget", provider: SnapshotProvider()) { entry in
            MetronomeWidgetView(entry: entry)
        }
        .configurationDisplayName("LAURENT 節拍")
        .description("目前 BPM 與拍號，點 START 直達節拍器並開始。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MetronomeWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "metronome")
                        .font(.system(size: 11, weight: .bold))
                    Text(entry.snapshot.metronomeLabel)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.snapshot.bpm)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.6)
                }

                Text("\(entry.snapshot.timeSignature) · \(entry.snapshot.timbreName)")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.65)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if family == .systemMedium {
                Spacer(minLength: 0)
                startLink
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Color(red: 0.07, green: 0.07, blue: 0.09)
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "laurent-acoustic://metronome"))
        .overlay(alignment: .bottomTrailing) {
            if family == .systemSmall {
                startLink
            }
        }
    }

    private var startLink: some View {
        Link(destination: URL(string: "laurent-acoustic://metronome/start")!) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("START")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.04, green: 0.52, blue: 1.0), in: Capsule())
        }
    }
}

// MARK: - 節拍器 Live Activity（鎖屏＋靈動島）

struct MetronomeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MetronomeActivityAttributes.self) { context in
            // 鎖屏／橫幅面：BPM 大字＋拍號＋拍點列。
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isCountIn ? "預備拍" : "節拍器")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(context.state.bpm)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("BPM · \(context.state.timeSignature)")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.65)
                    }
                }
                Spacer()
                beatDots(state: context.state, dotSize: 11)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.07, green: 0.07, blue: 0.09))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(context.state.bpm)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("BPM")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(context.state.timeSignature)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(context.state.isCountIn ? "預備拍" : "第 \(context.state.beat) 拍")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    beatDots(state: context.state, dotSize: 9)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "metronome")
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
            } compactTrailing: {
                Text("\(context.state.bpm)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "metronome")
                    .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))
            }
            .keylineTint(Color(red: 0.04, green: 0.52, blue: 1.0))
        }
    }

    /// 拍點列：目前拍亮藍（預備拍琥珀）、已過拍半亮、未到拍暗。
    private func beatDots(state: MetronomeActivityAttributes.ContentState,
                          dotSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, state.beatsInBar), id: \.self) { index in
                Circle()
                    .fill(dotColor(state: state, index: index))
                    .frame(width: dotSize, height: dotSize)
            }
        }
    }

    private func dotColor(state: MetronomeActivityAttributes.ContentState,
                          index: Int) -> Color {
        if index == state.beat - 1 {
            return state.isCountIn
                ? Color(red: 1.0, green: 0.62, blue: 0.04)
                : Color(red: 0.04, green: 0.52, blue: 1.0)
        }
        return Color.white.opacity(index < state.beat - 1 ? 0.45 : 0.18)
    }
}
