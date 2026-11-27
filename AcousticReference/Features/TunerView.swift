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
    @State private var glideEngaged = false
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

                    // 【返修批3・版面重排】主顯示上方的工具列：
                    // 全螢幕鈕（左）與頻閃／指針分段（右）自成
                    // 一列——批2 以「空白角」為由把兩鈕浮在顯示
                    // 區角上，實機頻閃外環直達角位、兩鈕直接壓
                    // 在環上（Laurent 截圖點名遮擋＋全歪）。自
                    // 成一列後遮擋在結構上不可能發生；顯示區本
                    // 身只保留削波警示覆蓋（瞬時警示、母本同義）。
                    HStack(alignment: .center) {
                        immersiveButton(theme: theme)
                        Spacer(minLength: 0)
                        displayModeToggle(theme: theme)
                    }
                    .frame(height: 26)

                    TunerLiveDisplay(render: viewModel.render, engine: engine, store: store, theme: theme, gaugeHeight: gaugeHeight)

                    TunerNoteRow(render: viewModel.render, viewModel: viewModel, store: store, theme: theme, noteSize: noteSize, octaveSize: octaveSize, justStripExpanded: $justStripExpanded)

                    statusHint(theme: theme)

                    if !performance {
                        targetStrip(theme: theme)
                    }

                    TunerDataCard(render: viewModel.render, viewModel: viewModel, engine: engine, store: store, theme: theme)

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
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationBackground { theme.background }
        }
        .fullScreenCover(isPresented: $showImmersive) {
            ImmersiveTunerView(viewModel: viewModel, render: viewModel.render, engine: engine, store: store)
                .presentationBackground(.black)
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

    // MARK: - Row 1：樂器觸發鈕＋記譜/實音分段（母本行 5231）

    private func headerRow(theme: TunerTheme) -> some View {
        // 【裝機返修】撤 GlassEffectContainer 包裹（合成通道
        // 疑似造成樂器卡重影，見 TunerTheme.GlassSurface 註解）。
        HStack(spacing: 8) {
            // 【返修批3】卡身改 HStack＋onTapGesture（原為
            // Button 包整卡）：卡內嵌收藏星 Button——Button
            // 內不能再嵌 Button，改手勢後星鈕獨立命中、卡身
            // 其餘區域點按開樂器庫，互不干擾。星與樂器庫共用
            // FavoriteStarButton（爆裂參數單一真源）。
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.localizedName(store.selectedInstrument.categoryLabel))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(L10n.headerInstrumentLabel(name: store.selectedInstrument.name,
                                    englishName: store.selectedInstrument.englishName))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 4)
                FavoriteStarButton(store: store,
                                   instrumentId: store.selectedInstrument.id,
                                   theme: theme)
                Text(store.keyLabel(of: store.selectedInstrument))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.accent.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { showLibrary = true }

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
            fontSize: 12.5, height: 30)
            .frame(width: 128)
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
            .frame(width: 124)
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
                            .glassEffect(theme.glass(store.glassOpacity, interactive: true), in: Capsule())
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
                    glideEngaged = false
                    glideStartMinX = targetContentMinX
                    lastGlideChipId = glideChipId(at: value.startLocation)
                }
                // 【返修批2・按鍵審計】滑奏旗標改「真移動才
                // 置位」：舊版觸下即 setGliding(true)，純點按
                // 已鎖定晶片時 Button action 讀到 isGliding
                // == true、解除鎖定條件恆假（點了只能重鎖、
                // 解不掉）。現以位移 >8pt 或滑入另一晶片為
                // 置位門檻，純點按不再污染旗標。
                if !glideEngaged {
                    let moved = abs(value.translation.width) > 8
                        || abs(value.translation.height) > 8
                    let crossed = glideChipId(at: value.location) != nil
                        && glideChipId(at: value.location) != lastGlideChipId
                    if moved || crossed {
                        glideEngaged = true
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
                glideEngaged = false
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

/// 音高軌跡圖（返修批3 補回母本 .trace-wrap，規格見
/// docs/2026-11-27_母本規格提取-返修批3.md 第 2 節）：
/// 最近 8 秒音分曲線（右端最新）、縱軸 ±50¢、容差帶
/// （ok 8%）、中心虛線（muted 50%、[4,4]）、曲線下柔光
/// （accent 垂直漸變 0.023→0.11→0.023）、末端點（準音
/// ok／否則 accent）；nil 樣本斷筆；左上標籤、右上統計
/// 徽章（定格時 accent 底白字）；整槽點按切換定格；定格
/// 時 accent 邊框。麥克風關閉時改繪待機波形（緩漂正弦、
/// accent 28%＋±25¢ 參考線）。槽底：深 rgba(7,10,16,
/// 0.72)／淺 rgba(15,23,42,0.045)，邊框白／slate 8%。

// MARK: - 高速顯示區（返修批4・渲染隔離）

/// 主顯示區（頻閃／指針＋削波覆蓋＋舞台滑動）：本結構直接
/// 觀察 render（高頻），外殼 TunerView 只觀察 ViewModel
/// （現為低頻）與 store——分析幀到達時只重算本區，不再
/// 整頁重算（舊架構每幀整頁重算是指針卡頓與發燙的根因）。
struct TunerLiveDisplay: View {
    @ObservedObject var render: TunerRenderState
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    let theme: TunerTheme
    let gaugeHeight: CGFloat

    // 舞台左右滑（母本 wireStageSwipe）：主顯示區的推入動畫
    // 執行期值（自 ±14pt／0.35 透明回彈至原位，240 ms）。
    @State private var stageNudgeX: CGFloat = 0
    @State private var stageNudgeOpacity: Double = 1

    var body: some View {
        ZStack {
            Group {
                if store.tunerDisplayMode == .strobe {
                    StrobeView(
                        phase: render.strobePhase,
                        rate: render.strobeRate,
                        anchorDate: render.strobeAnchorDate,
                        confidence: render.strobeConfidence,
                        micActive: engine.isRunning,
                        inTune: render.isInTune,
                        theme: theme
                    )
                } else {
                    GaugeView(
                        cents: render.needleCents,
                        trail1Cents: render.trail1Cents,
                        trail2Cents: render.trail2Cents,
                        ghostCents: render.ghostCents,
                        ghostOpacity: render.ghostOpacity,
                        micActive: engine.isRunning,
                        inTune: render.isInTune,
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
        .overlay {
            if render.clipWarning {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(theme.clipWarning, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if render.clipWarning {
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
    }

    /// 主顯示本體的舞台左右滑手勢（母本 wireStageSwipe，行
    /// 6857）：|dx| ≥ 52 且 |dy| ≤ 36 時步進切換收藏樂器，
    /// 並播推入回彈動畫（自 dir 側 14pt／0.35 透明以
    /// cubic-bezier(0.22,1,0.36,1) 240 ms 回位）。
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
                stageNudgeX = dir > 0 ? 14 : -14
                stageNudgeOpacity = 0.35
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                    stageNudgeX = 0
                    stageNudgeOpacity = 1
                }
            }
    }
}

/// 音名行＋純律主音籤（返修批4・渲染隔離）：觀察 render，
/// 唱名／鎖定／準音色只在本區重算。viewModel 以普通 let
/// 傳入（只呼叫方法，不訂閱）。
struct TunerNoteRow: View {
    @ObservedObject var render: TunerRenderState
    let viewModel: TunerViewModel
    @ObservedObject var store: AppStore
    let theme: TunerTheme
    let noteSize: CGFloat
    let octaveSize: CGFloat
    @Binding var justStripExpanded: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(render.noteText)
                        .font(.system(size: noteSize, weight: .bold))
                        .foregroundStyle(noteColor)
                        .shadow(
                            color: (render.isInTune || render.noteLocked)
                                ? theme.ok.opacity(theme.isDark ? 0.42 : 0.28) : .clear,
                            radius: theme.isDark ? 11 : 7
                        )
                        .animation(.easeOut(duration: 0.18), value: render.isInTune)
                        .animation(.easeOut(duration: 0.18), value: render.noteLocked)

                    Text(render.octaveText)
                        .font(.system(size: octaveSize, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }

            // 唱名標籤（母本 .solfege-tag；鎖定時轉 ok 色，母本行 3398）。
            Text(L10n.t(render.solfegeText))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(render.noteLocked ? theme.ok : theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
                .overlay {
                    Capsule().strokeBorder(
                        (render.noteLocked ? theme.ok : theme.accent).opacity(0.35),
                        lineWidth: 1
                    )
                }
                .animation(.easeOut(duration: 0.18), value: render.noteLocked)

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

        if store.tunerSettings.temperament == .just && justStripExpanded {
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
    }
    }

    private var noteColor: Color {
        if render.isInTune || render.noteLocked { return theme.okText }
        if !render.hasNote { return theme.textMuted }
        return theme.textPrimary
    }
}

/// 數據卡（返修批4・渲染隔離）：四格讀數＋音高軌跡＋穩定度
/// 徽章收進同一張卡（母本單一 .data-card）。觀察 render；
/// 軌跡樣本取自 viewModel（每幀與 render 同步發布，見
/// TunerViewModel.ingest 註解）。
struct TunerDataCard: View {
    @ObservedObject var render: TunerRenderState
    let viewModel: TunerViewModel
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    let theme: TunerTheme

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                metricBox(theme: theme, label: "WRITTEN " + L10n.t("记谱"), value: render.writtenText)
                metricBox(theme: theme, label: "CONCERT " + L10n.t("实音"), value: render.concertText)
                metricBox(
                    theme: theme, label: "CENTS " + L10n.t("音分"),
                    value: render.centsDisplayText,
                    valueColor: render.isInTune ? theme.ok : theme.textPrimary
                )
                metricBox(theme: theme, label: "FREQ " + L10n.t("频率"), value: render.frequencyText)
            }

            PitchTraceView(
                samples: viewModel.traceSamples,
                tolerance: engine.settings.toleranceCents,
                frozen: render.stabilityFrozen,
                micActive: engine.isRunning,
                badgeText: render.stabilityBadgeText,
                theme: theme,
                onTap: { viewModel.toggleFreeze() })
                .frame(minHeight: 52, maxHeight: 196)
                .layoutPriority(1)
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
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                         theme: theme, glassOpacity: store.glassOpacity)
    }
}


struct PitchTraceView: View {
    let samples: [(t: TimeInterval, cents: Double?)]
    let tolerance: Double
    let frozen: Bool
    let micActive: Bool
    let badgeText: String
    let theme: TunerTheme
    let onTap: () -> Void

    private static let span: TimeInterval = 8.0
    private static let range: Double = 50

    private var hasSignal: Bool {
        micActive || samples.contains { $0.cents != nil }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if hasSignal {
                Canvas { ctx, size in drawTrace(in: &ctx, size: size) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 25.0)) { context in
                    Canvas { ctx, size in
                        drawIdle(in: &ctx, size: size,
                                 ts: context.date.timeIntervalSince1970)
                    }
                }
            }
            Text(L10n.t("音高轨迹") + " · PITCH TRACE")
                .font(.system(size: 8.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(theme.textMuted)
                .padding(.top, 5)
                .padding(.leading, 9)
            HStack {
                Spacer()
                Text(badgeText)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(frozen ? .white : theme.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(frozen ? theme.accent.opacity(0.78)
                                       : Color.white.opacity(theme.isDark ? 0.06 : 0.05),
                                in: Capsule())
                    .padding(.top, 4)
                    .padding(.trailing, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.isDark
                      ? Color(red: 7 / 255, green: 10 / 255, blue: 16 / 255).opacity(0.72)
                      : Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(frozen ? theme.accent.opacity(0.5)
                                     : (theme.isDark ? Color.white.opacity(0.08)
                                                     : Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.08)),
                              lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onTap() }
        .accessibilityLabel(L10n.t("音高轨迹"))
    }

    private func yFor(_ c: Double, h: CGFloat) -> CGFloat {
        let clamped = min(Self.range, max(-Self.range, c))
        return h / 2 - CGFloat(clamped / Self.range) * (h / 2 - 3)
    }

    private func drawTrace(in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        guard w > 4, h > 4, let last = samples.last else { return }
        // 容差帶
        let band = CGRect(x: 0, y: yFor(tolerance, h: h), width: w,
                          height: yFor(-tolerance, h: h) - yFor(tolerance, h: h))
        ctx.fill(Path(band), with: .color(theme.ok.opacity(0.08)))
        // 中心虛線
        var center = Path()
        center.move(to: CGPoint(x: 0, y: h / 2))
        center.addLine(to: CGPoint(x: w, y: h / 2))
        ctx.stroke(center, with: .color(theme.textMuted.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        // 連續段：柔光填充＋軌跡線
        let tEnd = last.t
        var segment: [CGPoint] = []
        func flush() {
            guard segment.count > 1 else { segment = []; return }
            var line = Path()
            line.move(to: segment[0])
            for p in segment.dropFirst() { line.addLine(to: p) }
            var fill = line
            fill.addLine(to: CGPoint(x: segment.last!.x, y: h))
            fill.addLine(to: CGPoint(x: segment.first!.x, y: h))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [theme.accent.opacity(0.023),
                                  theme.accent.opacity(0.11),
                                  theme.accent.opacity(0.023)]),
                startPoint: CGPoint(x: 0, y: h), endPoint: CGPoint(x: 0, y: 0)))
            ctx.stroke(line, with: .color(theme.accent.opacity(frozen ? 0.5 : 0.95)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            segment = []
        }
        for s in samples {
            guard let c = s.cents, c.isFinite else { flush(); continue }
            let x = w - CGFloat(tEnd - s.t) / CGFloat(Self.span) * w
            if x < -4 { continue }
            segment.append(CGPoint(x: max(0, x), y: yFor(c, h: h)))
        }
        flush()
        // 末端點（最新有效樣本）
        if let newest = samples.last(where: { $0.cents?.isFinite == true }),
           let c = newest.cents {
            let x = w - CGFloat(tEnd - newest.t) / CGFloat(Self.span) * w
            let p = CGPoint(x: max(0, x), y: yFor(c, h: h))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.8, y: p.y - 2.8,
                                            width: 5.6, height: 5.6)),
                     with: .color(abs(c) <= tolerance ? theme.ok : theme.accent))
        }
    }

    /// 待機波形（母本待機正弦）：緩漂正弦＋同色填充、
    /// ±25¢ 參考線、虛線中心、容差帶。
    private func drawIdle(in ctx: inout GraphicsContext, size: CGSize, ts: TimeInterval) {
        let w = size.width
        let h = size.height
        guard w > 4, h > 4 else { return }
        let band = CGRect(x: 0, y: yFor(tolerance, h: h), width: w,
                          height: yFor(-tolerance, h: h) - yFor(tolerance, h: h))
        ctx.fill(Path(band), with: .color(theme.ok.opacity(0.07)))
        for ref in [-25.0, 25.0] {
            var r = Path()
            r.move(to: CGPoint(x: 0, y: yFor(ref, h: h)))
            r.addLine(to: CGPoint(x: w, y: yFor(ref, h: h)))
            ctx.stroke(r, with: .color(theme.textMuted.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 1))
        }
        var center = Path()
        center.move(to: CGPoint(x: 0, y: h / 2))
        center.addLine(to: CGPoint(x: w, y: h / 2))
        ctx.stroke(center, with: .color(theme.textMuted.opacity(0.42)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        let amp = h * 0.15 * (0.7 + 0.3 * sin(ts / 2.6))
        var line = Path()
        let steps = max(2, Int(w))
        for i in 0...steps {
            let x = CGFloat(i)
            let y = h / 2
                + CGFloat(sin(Double(x) / 57 + ts / 0.9)) * amp * 0.4
                + CGFloat(sin(Double(x) / 23 - ts / 1.4)) * amp * 0.18
            if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
            else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        var fill = line
        fill.addLine(to: CGPoint(x: w, y: h))
        fill.addLine(to: CGPoint(x: 0, y: h))
        fill.closeSubpath()
        ctx.fill(fill, with: .color(theme.accent.opacity(0.07)))
        ctx.stroke(line, with: .color(theme.accent.opacity(0.28)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}
#Preview {
    TunerView(engine: AudioEngine(), store: AppStore(), drone: DroneEngine())
}
