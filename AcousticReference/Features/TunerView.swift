import SwiftUI

/// 調音主畫面（階段 4 補完）：版面自上而下對照母本調音面板
/// （index.html 行 5230 起）：
/// Row 1 樂器觸發鈕（分類標籤＋樂器名＋調號籤）＋記譜/實音分段；
/// Row 2 收藏晶片列＋A4 步進器，其下收藏圓點指示（#25）；
/// Row 3 主顯示區（頻閃／錶盤可切換，頻閃主模式段）＋音名行
/// （唱名籤＋純律主音籤 #24 與主音快選列）；
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
    /// 橫屏沉浸全屏（階段 6）：fullScreenCover 呈現狀態；
    /// 切離調音模式時強制關閉（深連結等路徑），方向鎖的
    /// 還原由 ImmersiveTunerView.onDisappear 統一負責。
    @State private var showImmersive = false

    // 舞台左右滑（母本 wireStageSwipe）：主顯示區的推入動畫
    // 執行期值（自 ±14pt／0.35 透明回彈至原位，240 ms）。
    @State private var stageNudgeX: CGFloat = 0
    @State private var stageNudgeOpacity: Double = 1

    // 收藏拖曳排序（母本 wireFavChipDrag）：拖動中的晶片 id、
    // 水平位移、同列讓位狀態；frames 為長按拾起瞬間的快照
    // （拖動期間的 offset 會污染即時量測，判定一律用快照，
    // 與母本以 offsetLeft 佈局座標判定同義）。
    @State private var favChipFrames: [String: CGRect] = [:]
    @State private var favDragStartFrames: [String: CGRect] = [:]
    @State private var favDragId: String?
    @State private var favDragTranslation: CGFloat = 0
    @State private var favShifted: [String: Bool] = [:]
    @State private var favLastShiftCount = -1
    @State private var favSuppressTapUntil = Date.distantPast

    // 目標列滑奏（母本 stringChips glide）：晶片 frames（視口
    // 座標，與拖動 location 同空間）、內容左緣位置（判滑動
    // 是否其實是捲動）、滑奏狀態。
    @State private var targetChipFrames: [String: CGRect] = [:]
    @State private var targetContentMinX: CGFloat = 0
    @State private var glideActive = false
    @State private var glideBlocked = false
    @State private var glideStartMinX: CGFloat = 0
    @State private var lastGlideChipId: String?

    init(engine: AudioEngine, store: AppStore, drone: DroneEngine) {
        self.engine = engine
        self.store = store
        self.drone = drone
        _viewModel = StateObject(wrappedValue: TunerViewModel(
            engine: engine, store: store, drone: drone))
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        let performance = store.performanceMode

        GeometryReader { geo in
            // 母本 .pitch-note：clamp(36px, 6.4vh, 64px)；
            // .pitch-octave：clamp(16px, 2.8vh, 26px)。
            // 演奏態（補強段）：音名 ×1.12、主顯示高度預算
            // 0.30 → 0.46（輔助列隱藏後釋出的高度歸主顯示）。
            let noteSize = min(72, max(36, geo.size.height * 0.064)
                               * (performance ? 1.12 : 1))
            let octaveSize = min(26, max(16, geo.size.height * 0.028))
            let gaugeHeight = min(
                (geo.size.width - 32) * 190.0 / 320.0 * (performance ? 1.3 : 1),
                geo.size.height * (performance ? 0.46 : 0.30)
            )

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 8) {
                    headerRow(theme: theme)

                    if !performance {
                        favoritesRow(theme: theme)

                        favoritesDots(theme: theme)
                    }

                    // 主顯示區（頻閃主模式段）：頻閃（預設主模式）
                    // 與錶盤（輔助）共用同一高度預算，切換鈕浮在
                    // 顯示區右上角的空白角（兩種顯示在該角皆無
                    // 內容：錶盤弧線與頻閃外環都不及），不佔列高、
                    // 不擠壓任何既有列。左上角為演奏態開關（補強
                    // 段，同為空白角）；削波警示（補強段）以紅框
                    // 覆滿顯示區＋左下角小籤呈現，不遮擋讀數。
                    ZStack(alignment: .topTrailing) {
                        displayContent(theme: theme, gaugeHeight: gaugeHeight)

                        displayModeToggle(theme: theme)
                            .padding(.top, 2)
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            performanceToggle(theme: theme)
                            immersiveButton(theme: theme)
                        }
                        .padding(.top, 2)
                    }
                    .overlay {
                        if viewModel.clipWarning {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(theme.clipWarning, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if viewModel.clipWarning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(L10n.t("削波"))
                                    .font(.system(size: 10.5, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(theme.clipWarning, in: Capsule())
                            .padding(6)
                            .allowsHitTesting(false)
                            .accessibilityLabel(L10n.t("输入削波警示"))
                        }
                    }

                    noteRow(theme: theme, noteSize: noteSize, octaveSize: octaveSize)

                    if store.tunerSettings.temperament == .just && justStripExpanded {
                        justTonicStrip(theme: theme)
                    }

                    statusHint(theme: theme)

                    if !performance {
                        targetStrip(theme: theme)
                    }

                    metricsCard(theme: theme)

                    stabilityRow(theme: theme)

                    Spacer(minLength: 0)

                    if !performance {
                        droneCapsule(theme: theme)
                    }

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
        .fullScreenCover(isPresented: $showImmersive) {
            ImmersiveTunerView(viewModel: viewModel, engine: engine, store: store)
        }
        // 沉浸中被切離調音模式（深連結／外部路徑）：立即關閉
        // cover，方向鎖隨 onDisappear 還原豎屏（防漏）。
        .onChange(of: store.appMode) { _, newMode in
            if newMode != .tuner { showImmersive = false }
        }
        // 自動開啟麥克風（母本調音頁 pointerdown → ensureMicOn）：
        // autoMicOnEnter 開時點按頁面任意處即啟動；simultaneous
        // 不攔截任何既有手勢與按鈕，關時不觸發（母本預設關）。
        .simultaneousGesture(
            TapGesture().onEnded {
                if store.autoMicOnEnter, !engine.isRunning {
                    Task { await engine.start() }
                }
            }
        )
        .onDisappear { viewModel.viewDidDisappear() }
    }

    // MARK: - 主顯示內容（頻閃／指針＋舞台滑動）

    /// 主顯示本體：舞台左右滑手勢（母本 wireStageSwipe，行
    /// 6857）以 simultaneousGesture 掛在本體上——|dx| ≥ 52 且
    /// |dy| ≤ 36 時步進切換收藏樂器（左滑下一個、右滑上一個），
    /// 並播母本的推入回彈動畫（自 dir 側 14pt／0.35 透明以
    /// cubic-bezier(0.22,1,0.36,1) 240 ms 回位）。右上角的模式
    /// 切換鈕是 ZStack 的另一子層、不在本體命中路徑內，點按
    /// 不會武裝滑動（母本同：手勢只認 .tuner-stage 本體）。
    @ViewBuilder
    private func displayContent(theme: TunerTheme, gaugeHeight: CGFloat) -> some View {
        Group {
            if store.tunerDisplayMode == .strobe {
                StrobeView(
                    phase: viewModel.strobePhase,
                    rate: viewModel.strobeRate,
                    anchorDate: viewModel.strobeAnchorDate,
                    confidence: viewModel.strobeConfidence,
                    micActive: engine.isRunning,
                    inTune: viewModel.isInTune,
                    theme: theme
                )
            } else {
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
            }
        }
        .frame(height: gaugeHeight)
        .offset(x: stageNudgeX)
        .opacity(stageNudgeOpacity)
        .simultaneousGesture(stageSwipeGesture)
    }

    private var stageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) >= 52, abs(dy) <= 36 else { return }
                let dir = dx < 0 ? 1 : -1
                let before = store.selectedInstrumentId
                store.stepFavoriteInstrument(dir: dir)
                guard store.selectedInstrumentId != before else { return }
                // 母本 gaugeWrap.animate：自 ±14pt／0.35 回彈。
                stageNudgeX = dir > 0 ? 14 : -14
                stageNudgeOpacity = 0.35
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                    stageNudgeX = 0
                    stageNudgeOpacity = 1
                }
            }
    }

    /// 全屏鈕（母本 btnEnterImmersiveManual「全屏」，階段 6）：
    /// 與演奏態開關並列於主顯示左上角空白角（同列小膠囊，
    /// 不佔列高）；點按進橫屏沉浸（唯一合法橫屏狀態）。
    private func immersiveButton(theme: TunerTheme) -> some View {
        Button {
            showImmersive = true
            HapticsEngine.shared.tap(milliseconds: 6)
        } label: {
            Text(L10n.t("全屏"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(L10n.t("进入极简全屏调音"))
    }

    /// 演奏態開關（補強段）：開啟隱藏收藏／A4／目標音／Drone
    /// 列、主顯示放大；與暗紅模式、防誤觸鎖正交可疊加。
    private func performanceToggle(theme: TunerTheme) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                store.performanceMode.toggle()
            }
            HapticsEngine.shared.tap(milliseconds: 6)
        } label: {
            Image(systemName: store.performanceMode
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 26, height: 26)
                .glassBackground(in: Circle(), theme: theme, glassOpacity: store.glassOpacity)
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(store.performanceMode ? L10n.t("退出演奏态") : L10n.t("演奏态"))
    }

    // MARK: - Row 1：樂器觸發鈕＋記譜/實音分段（母本行 5231）

    private func headerRow(theme: TunerTheme) -> some View {
        // 【裝機返修】撤 GlassEffectContainer 包裹（合成通道
        // 疑似造成樂器卡重影，見 TunerTheme.GlassSurface 註解）。
        HStack(spacing: 8) {
            Button {
                showLibrary = true
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.localizedName(store.selectedInstrument.categoryLabel))
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(theme.accent)
                            .lineLimit(1)
                        Text(L10n.headerInstrumentLabel(name: store.selectedInstrument.name,
                                        englishName: store.selectedInstrument.englishName))
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
                .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
            }
            .buttonStyle(GlassPressButtonStyle())

            pitchModeSegment(theme: theme)
        }
    }

    /// 記譜／實音分段（母本 pitchModeSeg，行 5243）：切換寫入
    /// profile.pitchMode 並保存（母本行 8320）。【裝機返修】
    /// 改液態玻璃鏡片切換（Laurent 指定：所有選項控件皆然）。
    private func pitchModeSegment(theme: TunerTheme) -> some View {
        GlassSegmentedControl(
            options: [
                (option: PitchMode.written, title: L10n.t("记谱"), symbol: nil),
                (option: PitchMode.concert, title: L10n.t("实音"), symbol: nil),
            ],
            selection: Binding(
                get: { store.pitchMode },
                set: { store.pitchMode = $0 }),
            theme: theme, glassOpacity: store.glassOpacity,
            fontSize: 13, height: 30)
    }

    // MARK: - 主顯示模式切換（頻閃主模式段新增）

    /// 頻閃／指針分段（縮小版）：寫入 store.tunerDisplayMode
    /// 即存即生效；純顯示偏好，不觸碰引擎、判準與觸感。
    /// 【裝機返修】改液態玻璃鏡片切換。
    private func displayModeToggle(theme: TunerTheme) -> some View {
        GlassSegmentedControl(
            options: [
                (option: TunerDisplayMode.strobe, title: L10n.t("频闪"), symbol: nil),
                (option: TunerDisplayMode.needle, title: L10n.t("指针"), symbol: nil),
            ],
            selection: Binding(
                get: { store.tunerDisplayMode },
                set: { store.tunerDisplayMode = $0 }),
            theme: theme, glassOpacity: store.glassOpacity,
            fontSize: 12, height: 26)
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
                        Text(L10n.t("＋ 常用"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
                .padding(.vertical, 1)
                .onPreferenceChange(FavChipFrameKey.self) { frames in
                    favChipFrames = frames
                }
            }
            .coordinateSpace(.named("favBar"))

            a4Stepper(theme: theme)
        }
        .frame(height: 34)
    }

    /// 收藏晶片：點按選樂器（母本 selectInstrument 連重選也走
    /// 完整路徑、清鎖定；無觸感呼叫）；長按 200 ms 拾起拖曳
    /// 排序（母本 wireFavChipDrag，行 6611：拾起 haptic(10)、
    /// 讓位變化 haptic(5)、放下後 350 ms 內吞掉點按；拾起前
    /// 移動 >10pt 視為捲動、長按自動落空——母本為 8px，原生
    /// 以 LongPressGesture 的 maximumDistance 10 近似）。
    /// 與母本的差異（註明）：母本拖到邊緣會自動捲動收藏列，
    /// 原生未實作邊緣自動捲動（SwiftUI 無可靠的拖動中程式化
    /// 捲動通道）；收藏列在不拖動時照常可捲動，排序範圍以
    /// 可見晶片為限。
    private func favoriteChip(inst: Instrument, theme: TunerTheme) -> some View {
        let active = inst.id == store.selectedInstrumentId
        let isDragged = favDragId == inst.id
        return Text(L10n.localizedName(inst.name))
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background {
                GlassChipBackground(selected: active, theme: theme,
                                    glassOpacity: store.glassOpacity)
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(
                    key: FavChipFrameKey.self,
                    value: [inst.id: proxy.frame(in: .named("favBar"))])
            })
            .offset(x: isDragged ? favDragTranslation : favShiftOffset(for: inst.id))
            .scaleEffect(isDragged ? 1.07 : 1)
            .zIndex(isDragged ? 2 : 0)
            .onTapGesture {
                guard Date() >= favSuppressTapUntil else { return }
                store.selectInstrument(id: inst.id)
            }
            .gesture(favDragGesture(for: inst))
    }

    /// 同列讓位位移（母本 layout()：被跨越的同列晶片以
    /// −dir ×（被拖晶片寬＋間隔 6）讓位）。
    private func favShiftOffset(for id: String) -> CGFloat {
        guard let dragId = favDragId, id != dragId, favShifted[id] == true,
              let myFrame = favDragStartFrames[dragId],
              let frame = favDragStartFrames[id] else { return 0 }
        let dir: CGFloat = myFrame.midX < frame.midX ? 1 : -1
        return -dir * (myFrame.width + 6)
    }

    private func favDragGesture(for inst: Instrument) -> some Gesture {
        LongPressGesture(minimumDuration: 0.2, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                            coordinateSpace: .named("favBar")))
            .onChanged { value in
                guard case .second(_, let drag) = value, let drag else { return }
                if favDragId != inst.id {
                    favDragId = inst.id
                    favDragStartFrames = favChipFrames
                    favShifted = [:]
                    favLastShiftCount = -1
                    HapticsEngine.shared.tap(milliseconds: 10)
                }
                favDragTranslation = drag.translation.width
                updateFavShifts(draggedId: inst.id)
            }
            .onEnded { _ in
                if favDragId == inst.id {
                    commitFavDrag(draggedId: inst.id)
                }
                favDragId = nil
                favDragTranslation = 0
                favShifted = [:]
                favDragStartFrames = [:]
            }
    }

    /// 讓位判定（母本 layout()）：以被拖晶片中心（快照中心＋
    /// 位移）與同列中心比較，對稱 ±6 死區遲滯（已讓位者以
    /// 中心 −6  reclaim、未讓位者以中心 +6 讓位），防邊界抖動。
    private func updateFavShifts(draggedId: String) {
        guard let myFrame = favDragStartFrames[draggedId] else { return }
        let myCx = myFrame.midX + favDragTranslation
        var shiftCount = 0
        var newShifted: [String: Bool] = [:]
        for id in store.favoriteInstrumentIds where id != draggedId {
            guard let frame = favDragStartFrames[id] else { continue }
            let dir: CGFloat = myFrame.midX < frame.midX ? 1 : -1
            let was = favShifted[id] ?? false
            let crossed = dir == 1
                ? (was ? myCx > frame.midX - 6 : myCx >= frame.midX + 6)
                : (was ? myCx < frame.midX + 6 : myCx <= frame.midX - 6)
            newShifted[id] = crossed
            if crossed { shiftCount += 1 }
        }
        favShifted = newShifted
        if favLastShiftCount >= 0, shiftCount != favLastShiftCount {
            HapticsEngine.shared.tap(milliseconds: 5)
        }
        favLastShiftCount = shiftCount
    }

    /// 放下提交（母本 onUp）：以有效中心（被拖 = 快照中心＋
    /// 位移；同列 = 快照中心＋讓位位移）排序為新收藏序。
    private func commitFavDrag(draggedId: String) {
        favSuppressTapUntil = Date().addingTimeInterval(0.35)
        guard let myFrame = favDragStartFrames[draggedId] else { return }
        let myCx = myFrame.midX + favDragTranslation
        var centers: [(id: String, cx: CGFloat)] = []
        for id in store.favoriteInstrumentIds {
            guard let frame = favDragStartFrames[id] else { continue }
            if id == draggedId {
                centers.append((id, myCx))
            } else {
                var cx = frame.midX
                if favShifted[id] == true {
                    let dir: CGFloat = myFrame.midX < frame.midX ? 1 : -1
                    cx += -dir * (myFrame.width + 6)
                }
                centers.append((id, cx))
            }
        }
        let newOrder = centers.sorted { $0.cx < $1.cx }.map { $0.id }
        if newOrder.count == store.favoriteInstrumentIds.count {
            store.reorderFavorites(newOrder)
        }
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
            .buttonStyle(GlassPressButtonStyle())
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
        .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
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
            Text(L10n.t(viewModel.solfegeText))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(viewModel.noteLocked ? theme.ok : theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
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
                    Text("\(L10n.t("纯律")) · \(PitchMath.noteNames[store.tunerSettings.justTonicPc])")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
                        .overlay {
                            Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(GlassPressButtonStyle())
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
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background {
                                GlassChipBackground(selected: active, theme: theme,
                                                    glassOpacity: store.glassOpacity)
                            }
                    }
                    .buttonStyle(GlassPressButtonStyle())
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
            Text(L10n.t("轻点任意处开始校音"))
                .font(.system(size: 12.5))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 18)
        .opacity(engine.isRunning ? 0 : 1)
    }

    // MARK: - Row 4：目標音列（母本行 5282）

    /// 目標音列＋滑奏（母本 stringChips glide，行 8575）：手指
    /// 按住橫滑，經過的晶片逐一接管鎖定（經 ViewModel 的
    /// glide 路徑，Drone 改頻走滑音常數、聽感為滑奏）；若列
    /// 本身開始捲動（內容左緣位移 >2pt），判定為捲動而非
    /// 滑奏，立即站下並封鎖至手指抬起（母本 scroll 站下＋
    /// glideBlock 語義）。晶片 frames 與拖動 location 同在
    /// "targetStrip" 視口座標（捲動時兩者同步移動，命中判定
    /// 恆以手指當下位置為準——母本 elementFromPoint 等價）。
    private func targetStrip(theme: TunerTheme) -> some View {
        HStack(spacing: 6) {
            if store.selectedInstrument.isGuzheng {
                guzhengKeyMenu(theme: theme)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    targetChip(label: L10n.t("自动识别"), note: nil, isGreen: false,
                               chipId: "__auto__", theme: theme)
                    ForEach(viewModel.targetChipItems) { item in
                        targetChip(label: item.label, note: item.note,
                                   isGreen: item.isGreen, chipId: item.id,
                                   theme: theme)
                    }
                }
                .padding(.vertical, 1)
                .background(GeometryReader { proxy in
                    Color.clear.preference(
                        key: TargetContentFrameKey.self,
                        value: proxy.frame(in: .named("targetStrip")))
                })
                .onPreferenceChange(TargetChipFrameKey.self) { frames in
                    targetChipFrames = frames
                }
                .onPreferenceChange(TargetContentFrameKey.self) { frame in
                    targetContentMinX = frame.minX
                }
            }
            .coordinateSpace(.named("targetStrip"))
            .simultaneousGesture(targetGlideGesture)
        }
        .frame(height: 34)
    }

    /// 命中晶片 id（frames 為視口座標；自動識別晶片回 "__auto__"）。
    private func glideChipId(at point: CGPoint) -> String? {
        targetChipFrames.first { $0.value.contains(point) }?.key
    }

    private var targetGlideGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("targetStrip"))
            .onChanged { value in
                if !glideActive {
                    glideActive = true
                    glideBlocked = false
                    glideStartMinX = targetContentMinX
                    lastGlideChipId = glideChipId(at: value.startLocation)
                    if lastGlideChipId != nil {
                        viewModel.setGliding(true)
                    }
                }
                if abs(targetContentMinX - glideStartMinX) > 2, !glideBlocked {
                    glideBlocked = true
                    viewModel.setGliding(false)
                }
                guard !glideBlocked,
                      let chipId = glideChipId(at: value.location),
                      chipId != lastGlideChipId else { return }
                lastGlideChipId = chipId
                // 母本：滑入新晶片 = 觸發該晶片的 click()（含
                // haptic(5)＋tick）；click 內的取消切換以
                // !droneGlide 為條件，滑奏中恆不取消、只接管
                // 鎖定——原生 tapTargetChip 以 !isGliding 為
                // 同一條件，語義逐項等價（自動識別晶片 =
                // picked=nil 清除鎖定）。
                if chipId == "__auto__" {
                    viewModel.tapTargetChip(note: nil)
                } else if let item = viewModel.targetChipItems.first(where: { $0.id == chipId }) {
                    viewModel.tapTargetChip(note: item.note)
                }
            }
            .onEnded { _ in
                glideActive = false
                glideBlocked = false
                lastGlideChipId = nil
                viewModel.setGliding(false)
            }
    }

    /// 古箏調號選擇（母本 guzhengKeySelect，行 5284）：D、G、C、
    /// F、A；切換改寫有效移調與目標弦列（母本行 8613）。
    private func guzhengKeyMenu(theme: TunerTheme) -> some View {
        Menu {
            ForEach(InstrumentCatalog.guzhengKeyOrder, id: \.self) { key in
                Button(L10n.t("古筝 \(key)调")) { store.guzhengKey = key }
            }
        } label: {
            HStack(spacing: 3) {
                Text(L10n.t("古筝 \(store.guzhengKey)调"))
                    .font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
        }
    }

    private func targetChip(label: String, note: String?, isGreen: Bool,
                            chipId: String, theme: TunerTheme) -> some View {
        let label = L10n.localizedName(label)
        let active = note == nil
            ? viewModel.lockedTargetNote == nil
            : viewModel.lockedTargetNote == note
        return Button {
            viewModel.tapTargetChip(note: note)
        } label: {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(
                    active ? theme.textPrimary
                        : (isGreen ? theme.ok : theme.textPrimary))
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background {
                    GlassChipBackground(selected: active, theme: theme,
                                        glassOpacity: store.glassOpacity)
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(
                        key: TargetChipFrameKey.self,
                        value: [chipId: proxy.frame(in: .named("targetStrip"))])
                })
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - Row 5：數據卡（母本四格：WRITTEN／CONCERT／CENTS／FREQ）

    private func metricsCard(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            metricBox(theme: theme, label: "WRITTEN " + L10n.t("记谱"), value: viewModel.writtenText)
            metricBox(theme: theme, label: "CONCERT " + L10n.t("实音"), value: viewModel.concertText)
            metricBox(
                theme: theme, label: "CENTS " + L10n.t("音分"),
                value: viewModel.centsDisplayText,
                valueColor: viewModel.isInTune ? theme.ok : theme.textPrimary
            )
            metricBox(theme: theme, label: "FREQ " + L10n.t("频率"), value: viewModel.frequencyText)
        }
        .padding(10)
        .glassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
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
                    .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            }
            .buttonStyle(GlassPressButtonStyle())
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
                    Text(L10n.t(viewModel.droneButtonText))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(drone.isPlaying ? theme.ok : theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Rectangle()
                .fill(theme.textMuted.opacity(0.25))
                .frame(width: 1, height: 22)

            Menu {
                ForEach(DroneTimbre.allCases, id: \.self) { timbre in
                    Button {
                        store.droneTimbre = timbre
                        // 母本 setDroneTimbre：uiSound("tick")（行 10241）。
                        UISoundEngine.shared.play(.tick)
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
                    Text("\(L10n.t("音色")) \(store.droneTimbre.displayName)")
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
                Text(L10n.t("音高跟随"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.droneFollow ? theme.textPrimary : theme.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background {
                        if store.droneFollow {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(
                                    .regular.tint(theme.accent.opacity(0.38)).interactive(),
                                    in: Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
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
                Text(L10n.t("麦克风权限被拒绝，请到系统设置开启"))
                    .font(.footnote)
                    .foregroundStyle(theme.clipWarning)
            }
            if let error = engine.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(theme.clipWarning)
                    .multilineTextAlignment(.center)
            }
            if let droneError = drone.lastError {
                Text(droneError)
                    .font(.footnote)
                    .foregroundStyle(theme.clipWarning)
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
                    Text(engine.isRunning ? L10n.t("校音中 · 点击停止") : L10n.t("开启麦克风校音"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
                .overlay {
                    Capsule().strokeBorder(
                        theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(GlassPressButtonStyle())
        }
    }
}

/// 收藏晶片 frames 匯集（鍵 = 樂器 id，值 = "favBar" 座標 frame）。
private struct FavChipFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect],
                       nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 目標晶片 frames 匯集（鍵 = 晶片 id，值 = "targetStrip" 視口座標 frame）。
private struct TargetChipFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect],
                       nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 目標列內容整體 frame（"targetStrip" 座標）：minX 變化即
/// 內容捲動量，供滑奏／捲動判別。
private struct TargetContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

#Preview {
    TunerView(engine: AudioEngine(), store: AppStore(), drone: DroneEngine())
}
