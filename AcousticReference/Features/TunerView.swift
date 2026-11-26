import SwiftUI

/// 調音主畫面（階段 4 補完）：版面自上而下對照母本調音面板
/// （index.html 行 5230 起）：
/// Row 1 樂器觸發鈕（分類標籤＋樂器名＋調號籤）＋記譜/實音分段；
/// Row 2 收藏晶片列＋A4 步進器，其下收藏圓點指示（#25）；
/// Row 3 錶盤＋音名行（唱名籤＋純律主音籤 #24 與主音快選列）；
/// Row 4 目標音列（古箏調號選擇＋目標晶片橫滑）；
/// Row 5 四格數據卡＋穩定度徽章；底部 Drone 膠囊＋麥克風主按鈕。
/// 頂欄（品牌＋分段切換＋診斷入口）在 ContentView 殼，本畫面不含。
/// 版面紀律同前：單欄直向堆疊、提示列與徽章列固定高度，狀態
/// 切換不重排、不遮擋、不重疊；尺寸錨定螢幕物理高。
struct TunerView: View {
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    @ObservedObject var drone: DroneEngine
    @StateObject private var viewModel: TunerViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var showLibrary = false
    @State private var justStripExpanded = false

    init(engine: AudioEngine, store: AppStore, drone: DroneEngine) {
        self.engine = engine
        self.store = store
        self.drone = drone
        _viewModel = StateObject(wrappedValue: TunerViewModel(
            engine: engine, store: store, drone: drone))
    }

    var body: some View {
        let theme = TunerTheme.resolve(colorScheme)

        GeometryReader { geo in
            // 母本 .pitch-note：clamp(36px, 6.4vh, 64px)；
            // .pitch-octave：clamp(16px, 2.8vh, 26px)。
            let noteSize = min(64, max(36, geo.size.height * 0.064))
            let octaveSize = min(26, max(16, geo.size.height * 0.028))
            let gaugeHeight = min(
                (geo.size.width - 32) * 190.0 / 320.0,
                geo.size.height * 0.30
            )

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 8) {
                    headerRow(theme: theme)

                    favoritesRow(theme: theme)

                    favoritesDots(theme: theme)

                    GaugeView(
                        cents: viewModel.needleCents,
                        trail1Cents: viewModel.trail1Cents,
                        trail2Cents: viewModel.trail2Cents,
                        ghostCents: viewModel.ghostCents,
                        ghostOpacity: viewModel.ghostOpacity,
                        micActive: engine.isRunning,
                        inTune: viewModel.isInTune,
                        tolerance: engine.settings.toleranceCents,
                        theme: theme
                    )
                    .frame(height: gaugeHeight)

                    noteRow(theme: theme, noteSize: noteSize, octaveSize: octaveSize)

                    if store.tunerSettings.temperament == .just && justStripExpanded {
                        justTonicStrip(theme: theme)
                    }

                    statusHint(theme: theme)

                    targetStrip(theme: theme)

                    metricsCard(theme: theme)

                    stabilityRow(theme: theme)

                    Spacer(minLength: 0)

                    droneCapsule(theme: theme)

                    micControls(theme: theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
        }
        .sheet(isPresented: $showLibrary) {
            InstrumentLibraryView(store: store)
        }
        .onDisappear { viewModel.viewDidDisappear() }
    }

    // MARK: - Row 1：樂器觸發鈕＋記譜/實音分段（母本行 5231）

    private func headerRow(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            Button {
                showLibrary = true
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.selectedInstrument.categoryLabel)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                        Text(store.selectedInstrument.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(store.keyLabel(of: store.selectedInstrument))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.accent.opacity(0.14), in: Capsule())
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            pitchModeSegment(theme: theme)
        }
    }

    /// 記譜／實音分段（母本 pitchModeSeg，行 5243）：切換寫入
    /// profile.pitchMode 並保存（母本行 8320）。
    private func pitchModeSegment(theme: TunerTheme) -> some View {
        HStack(spacing: 2) {
            pitchModeButton(mode: .written, title: "記譜", theme: theme)
            pitchModeButton(mode: .concert, title: "實音", theme: theme)
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func pitchModeButton(mode: PitchMode, title: String,
                                 theme: TunerTheme) -> some View {
        let active = store.pitchMode == mode
        return Button {
            guard store.pitchMode != mode else { return }
            store.pitchMode = mode
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? .white : theme.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(active ? theme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 2：收藏晶片列＋A4 步進器（母本行 5252）

    private func favoritesRow(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.favoriteInstrumentIds, id: \.self) { id in
                        if let inst = store.instrument(id: id) {
                            favoriteChip(inst: inst, theme: theme)
                        }
                    }
                    Button {
                        showLibrary = true
                    } label: {
                        Text("＋ 常用")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 1)
            }

            a4Stepper(theme: theme)
        }
        .frame(height: 34)
    }

    private func favoriteChip(inst: Instrument, theme: TunerTheme) -> some View {
        let active = inst.id == store.selectedInstrumentId
        return Button {
            // 母本收藏晶片點按：selectInstrument(found, true)，
            // 連同名重選也走完整選樂器路徑（清鎖定）；無觸感呼叫。
            store.selectInstrument(id: inst.id)
        } label: {
            Text(inst.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? .white : theme.textPrimary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(active ? theme.accent : Color.clear, in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A4 步進器（母本行 8630）：−／+ 單步 0.5 Hz、鉗 [430, 450]、
    /// 長按連調（340 ms 後每 62 ms，母本 addHoldRepeat）；每步一記
    /// detent 觸感（架構意見採納項）；讀數點按循環 440/442/443。
    private func a4Stepper(theme: TunerTheme) -> some View {
        HStack(spacing: 2) {
            HoldRepeatButton(action: {
                store.tunerSettings.stepA4(by: -0.5)
                HapticsEngine.shared.detent()
            }, label: {
                Text("−")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 30, height: 32)
            })
            Button {
                let presets = TunerSettings.a4Presets
                let next = presets.first { $0 > store.tunerSettings.a4 } ?? presets[0]
                store.tunerSettings.a4 = next
                HapticsEngine.shared.detent()
            } label: {
                Text(String(format: "A4=%.1f", store.tunerSettings.a4))
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            HoldRepeatButton(action: {
                store.tunerSettings.stepA4(by: 0.5)
                HapticsEngine.shared.detent()
            }, label: {
                Text("+")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 30, height: 32)
            })
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// 收藏圓點指示（母本 #25 renderFavDots，行 6883）：收藏 ≥2
    /// 才顯示，一收藏一圓點，active 跟隨目前樂器（不在收藏中
    /// 則無 active；1 個收藏顯示 0 圓點）。
    @ViewBuilder
    private func favoritesDots(theme: TunerTheme) -> some View {
        if store.favoriteInstrumentIds.count >= 2 {
            HStack(spacing: 5) {
                ForEach(store.favoriteInstrumentIds, id: \.self) { id in
                    Circle()
                        .fill(id == store.selectedInstrumentId
                              ? theme.accent : theme.textMuted.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 8)
        }
    }

    // MARK: - Row 3：音名行＋純律主音籤（母本行 5267）

    private func noteRow(theme: TunerTheme, noteSize: CGFloat, octaveSize: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(viewModel.noteText)
                    .font(.system(size: noteSize, weight: .bold))
                    .foregroundStyle(noteColor(theme: theme))
                    .shadow(
                        color: (viewModel.isInTune || viewModel.noteLocked)
                            ? theme.ok.opacity(theme.isDark ? 0.42 : 0.28) : .clear,
                        radius: theme.isDark ? 11 : 7
                    )
                    .animation(.easeOut(duration: 0.18), value: viewModel.isInTune)
                    .animation(.easeOut(duration: 0.18), value: viewModel.noteLocked)

                Text(viewModel.octaveText)
                    .font(.system(size: octaveSize, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
            }

            // 唱名標籤（母本 .solfege-tag；鎖定時轉 ok 色，母本行 3398）。
            Text(viewModel.solfegeText)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(viewModel.noteLocked ? theme.ok : theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        (viewModel.noteLocked ? theme.ok : theme.accent).opacity(0.35),
                        lineWidth: 1
                    )
                }
                .animation(.easeOut(duration: 0.18), value: viewModel.noteLocked)

            // 純律主音籤（母本 #24 justTonicPill）：僅純律時顯示，
            // 點按展開 12 音快選列；母本 haptic(6)。
            if store.tunerSettings.temperament == .just {
                Button {
                    HapticsEngine.shared.tap(milliseconds: 6)
                    withAnimation(.easeOut(duration: 0.18)) {
                        justStripExpanded.toggle()
                    }
                } label: {
                    Text("純律 · \(PitchMath.noteNames[store.tunerSettings.justTonicPc])")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 純律主音快選列（母本 justTonicStrip）：12 音晶片，選後
    /// 收合（母本行 7050）。
    private func justTonicStrip(theme: TunerTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<12, id: \.self) { pc in
                    let active = pc == store.tunerSettings.justTonicPc
                    Button {
                        viewModel.setJustTonic(pc)
                        justStripExpanded = false
                    } label: {
                        Text(PitchMath.noteNames[pc])
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(active ? .white : theme.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(active ? theme.accent : Color.clear, in: Capsule())
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(height: 30)
    }

    private func noteColor(theme: TunerTheme) -> Color {
        if viewModel.isInTune || viewModel.noteLocked { return theme.okText }
        if !viewModel.hasNote { return theme.textMuted }
        return theme.textPrimary
    }

    // MARK: - 狀態提示（固定高度，防重排）

    private func statusHint(theme: TunerTheme) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(theme.accent)
                .frame(width: 7, height: 7)
            Text("點擊下方「開啟麥克風校音」開始檢測")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 18)
        .opacity(engine.isRunning ? 0 : 1)
    }

    // MARK: - Row 4：目標音列（母本行 5282）

    private func targetStrip(theme: TunerTheme) -> some View {
        HStack(spacing: 6) {
            if store.selectedInstrument.isGuzheng {
                guzhengKeyMenu(theme: theme)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    targetChip(label: "自動識別", note: nil, isGreen: false, theme: theme)
                    ForEach(viewModel.targetChipItems) { item in
                        targetChip(label: item.label, note: item.note,
                                   isGreen: item.isGreen, theme: theme)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .frame(height: 34)
    }

    /// 古箏調號選擇（母本 guzhengKeySelect，行 5284）：D、G、C、
    /// F、A；切換改寫有效移調與目標弦列（母本行 8613）。
    private func guzhengKeyMenu(theme: TunerTheme) -> some View {
        Menu {
            ForEach(InstrumentCatalog.guzhengKeyOrder, id: \.self) { key in
                Button("古箏 \(key)調") { store.guzhengKey = key }
            }
        } label: {
            HStack(spacing: 3) {
                Text("古箏 \(store.guzhengKey)調")
                    .font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private func targetChip(label: String, note: String?, isGreen: Bool,
                            theme: TunerTheme) -> some View {
        let active = note == nil
            ? viewModel.lockedTargetNote == nil
            : viewModel.lockedTargetNote == note
        return Button {
            viewModel.tapTargetChip(note: note)
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(
                    active ? .white
                        : (isGreen ? theme.ok : theme.textPrimary))
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(active ? theme.accent : Color.clear, in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 5：數據卡（母本四格：WRITTEN／CONCERT／CENTS／FREQ）

    private func metricsCard(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            metricBox(theme: theme, label: "WRITTEN 記譜", value: viewModel.writtenText)
            metricBox(theme: theme, label: "CONCERT 實音", value: viewModel.concertText)
            metricBox(
                theme: theme, label: "CENTS 音分",
                value: viewModel.centsDisplayText,
                valueColor: viewModel.isInTune ? theme.ok : theme.textPrimary
            )
            metricBox(theme: theme, label: "FREQ 頻率", value: viewModel.frequencyText)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    private func metricBox(
        theme: TunerTheme, label: String, value: String, valueColor: Color? = nil
    ) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            theme.isDark ? Color.white.opacity(0.04) : Color.white.opacity(0.45),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    // MARK: - 穩定度徽章（母本 trace-stats-badge；輕點切換定格）

    private func stabilityRow(theme: TunerTheme) -> some View {
        HStack {
            Spacer()
            Button {
                viewModel.toggleFreeze()
            } label: {
                Text(viewModel.stabilityBadgeText)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(
                        viewModel.stabilityFrozen ? theme.accent : theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(height: 24)
    }

    // MARK: - Drone 膠囊（母本 droneCapsule，行 5397）

    private func droneCapsule(theme: TunerTheme) -> some View {
        HStack(spacing: 0) {
            Button {
                viewModel.toggleDrone()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: drone.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(viewModel.droneButtonText)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(drone.isPlaying ? theme.ok : theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(theme.textMuted.opacity(0.25))
                .frame(width: 1, height: 22)

            Menu {
                ForEach(DroneTimbre.allCases, id: \.self) { timbre in
                    Button {
                        store.droneTimbre = timbre
                    } label: {
                        if timbre == store.droneTimbre {
                            Label(timbre.displayName, systemImage: "checkmark")
                        } else {
                            Text(timbre.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("音色 \(store.droneTimbre.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
            }

            Rectangle()
                .fill(theme.textMuted.opacity(0.25))
                .frame(width: 1, height: 22)

            Button {
                viewModel.toggleDroneFollow()
            } label: {
                Text("音高跟隨")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.droneFollow ? .white : theme.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(store.droneFollow ? theme.accent : Color.clear, in: Capsule())
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                lineWidth: 1)
        }
    }

    // MARK: - 麥克風控制

    private func micControls(theme: TunerTheme) -> some View {
        VStack(spacing: 8) {
            if engine.permissionDenied {
                Text("麥克風權限被拒絕，請到系統設定開啟")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let error = engine.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let droneError = drone.lastError {
                Text(droneError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                if engine.isRunning {
                    engine.stop()
                } else {
                    Task { await engine.start() }
                }
            } label: {
                HStack(spacing: 9) {
                    Circle()
                        .fill(engine.isRunning ? theme.ok : theme.textMuted)
                        .frame(width: 9, height: 9)
                    Text(engine.isRunning ? "校音中 · 點擊停止" : "開啟麥克風校音")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    TunerView(engine: AudioEngine(), store: AppStore(), drone: DroneEngine())
}
