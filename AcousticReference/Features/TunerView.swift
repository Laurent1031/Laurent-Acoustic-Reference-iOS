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
    /// 【返修批11】選單改原生 sheet 卡片（與節拍器頁同
    /// 制，見 tunerPanelSheet）：批10 自製頁內面板實機
    /// 被否決，Laurent 定版「全部都要苹果原生生态」。
    @State private var tunerPanel: TunerPanel?

    private enum TunerPanel: String, Equatable, Identifiable {
        case droneTimbre, guzhengKey
        var id: String { rawValue }
    }


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
    /// 本次滑奏手勢的起點（全邏輯複查）：DragGesture 的
    /// startLocation 在單次手勢內恆定，作「新手指」判別
    /// ——glideActive 殘留時以起點變化偵測並重初始化。
    @State private var glideStartLocation: CGPoint?

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
            let availH = geo.size.height
            // 【返修批7・版面分級壓縮（深度檢查 E1/E3）】舊版面
            // 固定列高直接堆疊：16 Pro 級（可用 689）總高約
            // 741、溢出 ≈52（麥克風鈕壓進 Home Indicator 區）；
            // SE 級（可用 555）溢出 ≈136（麥克風鈕整顆出界）。
            // 改為：列間距／軌跡高按可用高分級收縮，主顯示高
            // 改由「可用高 − 固定列總高 − 間距 − 頁邊距」的
            // 餘量決定（下限 48，見 gaugeHeight 註），任何高度下總高恆 ≤ 可用高、
            // 不溢出、不重疊；餘量充裕時主顯示取自然高（與
            // 舊版的寬度／比例預算相同），視覺不變。
            let compact = availH < 660
            let rowSpacing: CGFloat = compact ? 5 : 6
            let traceHeight: CGFloat = compact ? 30 : 44
            // 【專屬規範 §A.6】音名尺寸 clamp(36, availH
            // ×0.064, 上限)：上限 72→56（寬裕級防過大）、
            // compact 級封頂 40（回收高度給主顯示）。
            let noteSize = min(compact ? 40 : 56,
                               max(36, availH * 0.064))
                * (performance ? 1.12 : 1)
            let octaveSize = min(26, max(16, availH * 0.028))
            let naturalGauge = min(
                (geo.size.width - 32) * 190.0 / 320.0 * (performance ? 1.3 : 1),
                availH * (performance ? 0.46
                          : (availH >= 740 ? 0.34 : 0.30))
            )
            // 固定列總高（不含主顯示與 Spacer），逐列對現行
            // 版面實高：樂器卡 40／工具列 32（五維審計 F5：
            // 分段控件實高＝傳入 26＋6，預算改按實高）／音
            // 名行 noteSize ×1.21／提示槽 18（訊息單槽輪替，
            // 恆高，見 statusHint）／麥克風鈕 45.5／數據卡
            // （上下內距 cardPad＋四格 47＋列距 8＋軌跡）。
            // 【返修批7 CI修復】ViewBuilder 閉包內不得出現賦值陳述
            // （其值 () 無法 conform to View）：以立即執行閉包
            // 算出固定列總高與列距數，數值與舊版逐列實高完全一致。
            let (fixedExcl, gaps): (CGFloat, Int) = {
                // 【專屬規範 §A.9】compact 瘦身打包：數據
                // 卡內距 20→16、收藏/目標列 34→32、軌跡
                // 30（見 traceHeight），合計回收 12pt 還
                // 主顯示（F5 工具列 +6 後 SE 主顯示曾被
                // 壓至 80 下限邊緣，本打包後 ≈90）。
                let cardPad: CGFloat = compact ? 16 : 20
                let stripH: CGFloat = compact ? 32 : 34
                var fixedExcl: CGFloat = 40 + 32 + noteSize * 1.21 + 18 + 45.5
                    + (cardPad + 47 + 8 + traceHeight)
                var gaps = 7 // 演奏態：8 列 − 1
                if !performance {
                    // 【專屬規範 §A.3】圓點列恆保留 8pt
                    // （收藏 <2 時為空位）：幾何恆定、預算
                    // 在任何間距解讀下精確（消 F6 歧義）。
                    fixedExcl += stripH /* 收藏列 */ + 8 /* 圓點列 */
                        + stripH /* 目標列 */ + 44 /* Drone */
                    gaps = 11
                }
                if justStripExpanded && store.tunerSettings.temperament == .just {
                    fixedExcl += 38 // 純律主音快選列 30＋列距 8
                }
                return (fixedExcl, gaps)
            }()
            let chrome = fixedExcl + CGFloat(gaps) * rowSpacing
                + 6 + (compact ? 8 : 10)
            // 【全邏輯複查・中】主顯示下限 80 在「compact＋
            // 純律快選列展開」時反致溢出：該組合 chrome ≈
            // 503、SE 可用高 555，餘量僅 ≈52，80 下限把總
            // 高頂到 583（溢出 ≈28、麥克風鈕被推出頁底）。
            // 下限改 48：鐵律「絕不溢出」優先於下限偏好；
            // 常規組合餘量 ≥ 80 時行為與舊版全等（SE 常規
            // ≈89.9、展開純律時 = 餘量 52 恰入頁）。
            let gaugeHeight = min(naturalGauge, max(48, availH - chrome))

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: rowSpacing) {
                    headerRow(theme: theme)

                    if !performance {
                        favoritesRow(theme: theme, compact: compact)

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
                    .frame(height: 32)

                    TunerLiveDisplay(render: viewModel.render, engine: engine, store: store, theme: theme, gaugeHeight: gaugeHeight)

                    TunerNoteRow(render: viewModel.render, viewModel: viewModel, store: store, theme: theme, noteSize: noteSize, octaveSize: octaveSize, justStripExpanded: $justStripExpanded)

                    statusHint(theme: theme)

                    if !performance {
                        targetStrip(theme: theme, compact: compact)
                    }

                    TunerDataCard(render: viewModel.render, viewModel: viewModel, engine: engine, store: store, theme: theme, traceHeight: traceHeight, pageVisible: store.appMode == .tuner, compact: compact)

                    Spacer(minLength: 0)

                    if !performance {
                        droneCapsule(theme: theme)
                    }

                    micControls(theme: theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, compact ? 8 : 10)

            }
        }
        .sheet(isPresented: $showLibrary) {
            InstrumentLibraryView(store: store)
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationBackground { theme.background }
        }
        // 【返修批11・原生卡片】Drone 音色／古箏調號的系
        // 統 sheet（見 tunerPanelSheet）。
        .sheet(item: $tunerPanel) { panel in
            tunerPanelSheet(panel, theme: theme)
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showImmersive) {
            ImmersiveTunerView(viewModel: viewModel, render: viewModel.render, engine: engine, store: store)
                .presentationBackground(.black)
        }
        // 沉浸中被切離調音模式（深連結／外部路徑）：立即關閉
        // cover，方向鎖隨 onDisappear 還原豎屏（防漏）。
        // 【返修批7・F11】同掛調音 DisplayLink 可見性門控：
        // 本頁在節拍器模式下不可見（雙頁保活），VM 的顯示
        // 時鐘停驅動；初值由下方 onAppear 補齊。
        .onChange(of: store.appMode) { _, newMode in
            if newMode != .tuner { showImmersive = false }
            viewModel.setPageVisible(newMode != .metronome)
        }
        .onAppear {
            viewModel.setPageVisible(store.appMode != .metronome)
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
        .onDisappear {
            viewModel.viewDidDisappear()
            // 手勢狀態兜底重置（審計修復）：收藏拖曳與目標列
            // 滑奏的狀態此前只在各自 onEnded 清理，系統中斷且
            // onEnded 未送達時 favDragId 殘留會令收藏列捲動
            // 鎖死（scrollDisabled 恆真）、isGliding 殘留令
            // Drone 滑音常數不復位；離頁一律歸零。
            favDragId = nil
            favDragTranslation = 0
            favShifted = [:]
            glideActive = false
            glideEngaged = false
            glideBlocked = false
            glideStartLocation = nil
            lastGlideChipId = nil
            viewModel.setGliding(false)
        }
    }

    // MARK: - Row 1：樂器觸發鈕＋記譜/實音分段（母本行 5231）

    private func headerRow(theme: TunerTheme) -> some View {
        // 【裝機返修】撤 GlassEffectContainer 包裹（合成通道
        // 疑似造成樂器卡重影，見 TunerTheme.GlassSurface 註解）。
        HStack(spacing: 8) {
            // 【返修批3】卡身改 HStack＋onTapGesture（原為
            // Button 包整卡）：卡內嵌收藏星 Button——Button
            // 內不能再嵌 Button。【審計修復】批 3 註解稱星鈕
            // 與卡身手勢「互不干擾」並不成立：父層 onTapGesture
            // 與子 Button 可同時觸發，點星可能連帶開樂器庫。
            // 改手勢分區：名稱區（含 Spacer）與調號籤各自掛
            // 點按開樂器庫，星鈕獨立於任何父手勢之外，命中
            // 互不重疊。星與樂器庫共用 FavoriteStarButton
            // （爆裂參數單一真源）。
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.localizedName(store.selectedInstrument.categoryLabel))
                            .font(.system(size: 10, weight: .bold))
                            // 【五維審計・排版項16】CJK 不施字距。
                            .tracking(L10n.isCJK ? 0 : 0.8)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { showLibrary = true }

                FavoriteStarButton(store: store,
                                   instrumentId: store.selectedInstrument.id,
                                   theme: theme)
                Text(store.keyLabel(of: store.selectedInstrument))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.accent.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { showLibrary = true }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)

            pitchModeSegment(theme: theme)
        }
    }

    /// 記譜／實音分段（母本 pitchModeSeg，行 5243）：切換寫入
    /// profile.pitchMode 並保存（母本行 8320）。
    /// 【返修批11・全原生化】改系統原生分段 Picker（同
    /// ContentView 主模式切換註），自製鏡片退役。
    private func pitchModeSegment(theme: TunerTheme) -> some View {
        Picker("", selection: Binding(
            get: { store.pitchMode },
            set: { store.pitchMode = $0 })) {
            Text(L10n.t("记谱")).tag(PitchMode.written)
            Text(L10n.t("实音")).tag(PitchMode.concert)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 128)
    }

    // MARK: - 主顯示模式切換（頻閃主模式段新增）

    /// 指針／頻閃分段（縮小版）：寫入 store.tunerDisplayMode
    /// 即存即生效；純顯示偏好，不觸碰引擎、判準與觸感。
    /// 【返修批10】次序［指針｜頻閃］（預設在左）。
    /// 【返修批11・全原生化】改系統原生分段 Picker。
    private func displayModeToggle(theme: TunerTheme) -> some View {
        Picker("", selection: Binding(
            get: { store.tunerDisplayMode },
            set: { store.tunerDisplayMode = $0 })) {
            Text(L10n.t("指针")).tag(TunerDisplayMode.needle)
            Text(L10n.t("频闪")).tag(TunerDisplayMode.strobe)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 124)
    }

    // MARK: - Row 2：收藏晶片列＋A4 步進器（母本行 5252）

    private func favoritesRow(theme: TunerTheme, compact: Bool) -> some View {
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
                // 【全邏輯複查・低】compact 列框 32：內容
                // 垂直 padding 歸零，內容實高 = 晶片 32 恰
                // 入列（舊版 +1 上下令實高 34、玻璃面被裁
                // 或溢入列距）；常規級維持 1（實高 34 = 列框）。
                .padding(.vertical, compact ? 0 : 1)
                .onPreferenceChange(FavChipFrameKey.self) { frames in
                    favChipFrames = frames
                }
            }
            .coordinateSpace(.named("favBar"))
            // 拖曳排序進行中鎖住捲動（返修批 5）：拾起後捲動與
            // 拖曳不再互搶；未拾起時捲動完全自由（見晶片手勢）。
            .scrollDisabled(favDragId != nil)

            a4Stepper(theme: theme)
        }
        // 【專屬規範 §A.9】compact 級列高 34→32（晶片本體
        // 32 不變、恰入列），與預算 stripH 同步。
        .frame(height: compact ? 32 : 34)
    }

    /// 收藏晶片：點按選樂器（母本 selectInstrument 連重選也走
    /// 完整路徑、清鎖定；無觸感呼叫）；長按 500 ms 拾起拖曳
    /// 排序（母本 wireFavChipDrag，行 6611：拾起 haptic(10)、
    /// 讓位變化 haptic(5)、放下後 350 ms 內吞掉點按；拾起前
    /// 移動 >8pt 視為捲動、長按自動落空——母本為 8px）。
    /// 與母本的差異（註明）：母本拖到邊緣會自動捲動收藏列，
    /// 原生未實作邊緣自動捲動（SwiftUI 無可靠的拖動中程式化
    /// 捲動通道）；收藏列在不拖動時照常可捲動，排序範圍以
    /// 可見晶片為限。
    /// 【返修批8】長按門檻 200 ms → 500 ms（iOS 系統長按
    /// 標準）：批5/7 的 200 ms 落在慢速捲動的起手停留窗內
    /// ——手指在晶片上慢推時，長按先成立、序列拖曳接管、
    /// scrollDisabled 再硬鎖，實機表現為「收藏列根本滑不
    /// 動、被遮住的晶片選不到」。500 ms 下任何真捲動都會
    /// 在門檻前移出 8pt 距離令長按落空，捲動完全自由；拾
    /// 起必須是原地按住半秒的明確意圖。
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
                // 【返修批8】防殭屍拖曳態：若拖曳狀態異常殘
                // 留（手勢被系統取消、onEnded 未送達），先清
                // 態再處理本次點按——scrollDisabled 隨之解
                // 除，收藏列不被永久鎖死。
                // 【全邏輯複查・中】清態改無條件：舊版只清
                // 「殘留在別顆晶片」的情形，殘留在同一顆時
                // 點按不清、鎖死持續到離頁。點按能送達即
                // 證明該晶片當下無進行中的拖曳（拖曳中觸
                // 碰由 sequenced 手勢獨佔、點按不觸發），
                // favDragId 非空必為殘留，清之恆安全。
                if favDragId != nil {
                    favDragId = nil
                    favDragTranslation = 0
                    favShifted = [:]
                    favDragStartFrames = [:]
                }
                guard Date() >= favSuppressTapUntil else { return }
                store.selectInstrument(id: inst.id)
            }
            // 返修批 5：改 simultaneousGesture。此前以獨佔
            // .gesture 掛長按＋拖曳序列，SwiftUI 手勢仲裁令
            // ScrollView 必須等此手勢失敗才捲動。改並行後
            // 快速滑動長按自動落空、捲動即時跟手；拾起後由
            // favoritesRow 的 scrollDisabled 鎖住捲動專心
            // 排序。拾起門檻的 500 ms 化見晶片頭註（批8）。
            .simultaneousGesture(favDragGesture(for: inst))
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
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 2,
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
        // 【專屬規範 §A.3】恆佔 8pt：收藏 <2 時渲染空位，
        // 幾何恆定（預算不再隨收藏數變動）。
        Group {
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
            }
        }
        .frame(height: 8)
    }

    // MARK: - 狀態提示（固定高度，防重排）

    private func statusHint(theme: TunerTheme) -> some View {
        // 【五維審計 F1／專屬規範 §A.7】訊息單槽輪替：
        // 權限被拒 ＞ 引擎錯誤 ＞ Drone 錯誤 ＞ 操作提示，
        // 恆高 18。舊版三條訊息列掛在麥克風區內且未入
        // 頁面預算——權限被拒/錯誤態下每列令總高 +25，
        // 把控制座推出頁底（首次拒權限即觸發）。單槽後
        // 任何狀態下頁面總高不變、控制座永不位移。
        let slotError = engine.permissionDenied
            ? nil : (engine.lastError ?? drone.lastError)
        return HStack(spacing: 7) {
            if engine.permissionDenied {
                Circle()
                    .fill(theme.clipWarning)
                    .frame(width: 7, height: 7)
                Text(L10n.t("麦克风权限被拒绝，请到系统设置开启"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.clipWarning)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(L10n.t("前往设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(theme.accent)
            } else if let error = slotError {
                Circle()
                    .fill(theme.clipWarning)
                    .frame(width: 7, height: 7)
                Text(L10n.t(error))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.clipWarning)
                    .lineLimit(1)
            } else if viewModel.noSignal {
                // 【專屬規範 S-1】無訊號自報：不留「校音中」
                // 假運行態（數據卡頻率格同步顯示「—」）。
                Circle()
                    .fill(theme.clipWarning)
                    .frame(width: 7, height: 7)
                Text(L10n.t("未收到讯号 · 检查麦克风"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.clipWarning)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 7, height: 7)
                Text(L10n.t("轻点任意处开始校音"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(height: 18)
        .opacity(!engine.permissionDenied && slotError == nil
                 && !viewModel.noSignal
                 && engine.isRunning ? 0 : 1)
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
    private func targetStrip(theme: TunerTheme, compact: Bool) -> some View {
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
                // 【全邏輯複查・低】同收藏列：compact 時
                // 垂直 padding 歸零，內容實高 32 恰入列框。
                .padding(.vertical, compact ? 0 : 1)
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
        // 【專屬規範 §A.9】compact 級列高 34→32（同收藏列）。
        .frame(height: compact ? 32 : 34)
    }

    /// 命中晶片 id（frames 為視口座標；自動識別晶片回 "__auto__"）。
    private func glideChipId(at point: CGPoint) -> String? {
        targetChipFrames.first { $0.value.contains(point) }?.key
    }

    private var targetGlideGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("targetStrip"))
            .onChanged { value in
                // 【全邏輯複查・中】殘留自癒：手勢被系統取
                // 消時 onEnded 不送達，glideActive 等狀態殘
                // 留會污染下一次手勢（跳過初始化、起點基準
                // 錯位、首顆接管被吞）。startLocation 在單
                // 次手勢內恆定：已 active 而起點不同 = 新
                // 手指、舊態必為殘留，強制重初始化（VM 的
                // isGliding 一併落下，下方流程按新態重建）。
                if glideActive, glideStartLocation != value.startLocation {
                    glideActive = false
                    viewModel.setGliding(false)
                }
                if !glideActive {
                    glideActive = true
                    glideBlocked = false
                    glideEngaged = false
                    glideStartMinX = targetContentMinX
                    glideStartLocation = value.startLocation
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
                glideStartLocation = nil
                lastGlideChipId = nil
                viewModel.setGliding(false)
            }
    }

    /// 古箏調號選擇（母本 guzhengKeySelect，行 5284）：D、G、C、
    /// F、A；切換改寫有效移調與目標弦列（母本行 8613）。
    private func guzhengKeyMenu(theme: TunerTheme) -> some View {
        // 【返修批11】改原生 sheet 卡片開關鈕（同 Drone 音色）。
        Button {
            tunerPanel = .guzhengKey
            HapticsEngine.shared.tap(milliseconds: 4)
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
        .buttonStyle(GlassPressButtonStyle())
    }

    // MARK: - 原生選單卡片（返修批11・與節拍器頁同制）

    /// 【返修批11・蘋果原生卡片】系統 sheet 內容：原生
    /// NavigationStack＋List（系統材質、原生行高），勾
    /// 在行右、右上「完成」鈕、可下滑收起。取代批10
    /// 自製玻璃面板（Laurent 定版全原生生態）。
    private func tunerPanelSheet(_ panel: TunerPanel, theme: TunerTheme) -> some View {
        NavigationStack {
            List {
                Section {
                    switch panel {
                    case .droneTimbre:
                        ForEach(DroneTimbre.allCases, id: \.self) { timbre in
                            tunerSheetRow(theme: theme, title: timbre.displayName,
                                          checked: store.droneTimbre == timbre) {
                                store.droneTimbre = timbre
                                // 母本 setDroneTimbre：uiSound("tick")（行 10241）。
                                UISoundEngine.shared.play(.tick)
                                tunerPanel = nil
                            }
                        }
                    case .guzhengKey:
                        ForEach(InstrumentCatalog.guzhengKeyOrder, id: \.self) { key in
                            tunerSheetRow(theme: theme, title: L10n.t("古筝 \(key)调"),
                                          checked: store.guzhengKey == key) {
                                store.guzhengKey = key
                                tunerPanel = nil
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(panel == .droneTimbre
                             ? L10n.t("音色")
                             : L10n.t("古筝 \(store.guzhengKey)调"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("完成")) { tunerPanel = nil }
                }
            }
        }
    }

    /// 原生選項行（與節拍器頁 sheetRow 同形制）。
    private func tunerSheetRow(theme: TunerTheme, title: String, checked: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func targetChip(label: String, note: String?, isGreen: Bool,
                            chipId: String, theme: TunerTheme) -> some View {
        let label = L10n.localizedName(label)
        let active = note == nil
            ? viewModel.lockedTargetNote == nil
            : viewModel.lockedTargetNote == note
        return Button {
            // 【全邏輯複查・中】滑奏殘留自癒：VM 的
            // isGliding 若因手勢被系統取消而殘留 true，
            // 「再點已鎖定晶片取消鎖定」會被 !isGliding
            // 條件恆擋。點按能送達即證明當下無進行中的
            // 滑奏（glideActive 為 false），殘留旗標先落
            // 下再走正常點按語義。
            if !glideActive, viewModel.isGliding {
                viewModel.setGliding(false)
            }
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

    // MARK: - 全屏入口與 Drone 膠囊（母本行 10217）

    // 【審計修復・返修批6】批 4 抽子視圖重構時 immersiveButton 與
    // droneCapsule 兩函數遺失（呼叫點在、定義不在，當前樹無法
    // 編譯）；此處由批 3 版本（commit 559bed3）原樣恢復——VM 側
    // toggleDrone／toggleDroneFollow／droneButtonText 與 drone
    // 觀察物件接線一直都在，只缺 View 函數本體。
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

            // 【返修批11】改原生 sheet 卡片開關鈕（見
            // tunerPanelSheet）：形制與節拍器頁一致。
            Button {
                tunerPanel = .droneTimbre
                HapticsEngine.shared.tap(milliseconds: 4)
            } label: {
                HStack(spacing: 4) {
                    Text("\(L10n.t("音色")) \(store.droneTimbre.displayName)")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        // 【五維審計・排版項13】長譯文縮放兜底。
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Rectangle()
                .fill(theme.textMuted.opacity(0.25))
                .frame(width: 1, height: 22)

            Button {
                viewModel.toggleDroneFollow()
            } label: {
                Text(L10n.t("音高跟随"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
        // 【五維審計・設計項5】手繪平色描邊刪除（同麥克風
        // 鈕理由）：批9 漸變描邊為唯一真源。
    }

    // MARK: - 麥克風控制

    @Environment(\.openURL) private var openURL

    private func micControls(theme: TunerTheme) -> some View {
        // 訊息已移入 statusHint 單槽（五維審計 F1）：本區
        // 恆為按鈕本體 45.5，控制座在任何狀態下不位移。
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
                    // 【五維審計・排版項7】兩頁主 CTA 字重
                    // 統一 16 bold（本鈕原 semibold、節拍器
                    // START 為 bold）；長譯文（俄語 37 字）
                    // 單行＋縮放下限，防換行撐高按鈕。
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            // 【五維審計・設計項5】原手繪平色描邊疊在
            // glassBackground 的批9 漸變描邊之上、整圈蓋
            // 住漸變——刪除，描邊以令牌漸變為唯一真源。
        }
        .buttonStyle(GlassPressButtonStyle())
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
/// 徽章收進同一張卡（母本單一 .data-card）。
/// 【返修批7・F6】靜態殼與動態內容分離（輕版）：本殼只
/// 觀察 store（玻璃透明度，低頻），外層玻璃面＋描邊不隨
/// render 的逐幀發布重建；動態內容收進 TunerDataCardContent
/// 單獨觀察 render（軌跡樣本取自 viewModel，每幀與 render
/// 同步發布，見 TunerViewModel.ingest 註解）。
struct TunerDataCard: View {
    @ObservedObject var render: TunerRenderState
    let viewModel: TunerViewModel
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    let theme: TunerTheme
    /// 軌跡高（返修批7 版面分級壓縮）：由 TunerView 按可用
    /// 高度決定，取代舊 minHeight 52 的不確定落點。
    var traceHeight: CGFloat = 44
    /// 頁面可見性（返修批7 F5）：不可見時待機波動畫暫停。
    var pageVisible: Bool = true
    /// compact 級（專屬規範 §A.9）：內距 10→8（預算
    /// cardPad 16 與此同步）。
    var compact: Bool = false

    var body: some View {
        TunerDataCardContent(
            render: render, viewModel: viewModel, engine: engine,
            store: store, theme: theme,
            traceHeight: traceHeight, pageVisible: pageVisible)
            .padding(compact ? 8 : 10)
            .glassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
            // 【五維審計・設計項5】手繪平色描邊刪除（同麥
            // 克風鈕理由）：批9 漸變描邊為唯一真源。
    }
}

/// 數據卡動態內容（返修批7・F6 分離）：觀察 render／
/// engine，四格讀數各為獨立 MetricBox，軌跡為 Canvas 本體。
private struct TunerDataCardContent: View {
    @ObservedObject var render: TunerRenderState
    // 【全邏輯複查・中】VM 改觀察持有：舊版以 let 持有，
    // S-1 的 noSignal 翻轉只觸發 TunerView 本體重繪，
    // 本結構（輸入未變的子視圖）可被 SwiftUI 跳過重
    // 算——靜默場景下 render/engine/store 皆無新發布，
    // 頻率格的「—」不保證出現。VM 為低頻對象（鎖定
    // 目標/noSignal 等），觀察它不破壞返修批 4 隔離。
    @ObservedObject var viewModel: TunerViewModel
    @ObservedObject var engine: AudioEngine
    @ObservedObject var store: AppStore
    let theme: TunerTheme
    var traceHeight: CGFloat = 44
    var pageVisible: Bool = true

    /// 數據卡標籤組裝（排版項1）：英文介面＝前綴＋譯文，
    /// 其餘語言＝純譯文（格寬不足以容納雙語）。
    private func metricLabel(_ prefix: String, _ key: String) -> String {
        store.language == .en ? prefix + " " + L10n.t(key) : L10n.t(key)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // 【五維審計・排版項1】標籤原為「英文前綴＋
                // 譯文」雙語拼接：格寬 ≈74pt 下德語
                // 「WRITTEN Notiert」≈84pt、俄語 ≈96pt 必
                // 被截斷。改：英文介面保留雙語（其母本
                // 觀感），其餘語言只顯示譯文＋縮放下限
                // 0.75 兜底。
                MetricBox(theme: theme, glassOpacity: store.glassOpacity,
                          label: metricLabel("WRITTEN", "记谱"), value: render.writtenText)
                MetricBox(theme: theme, glassOpacity: store.glassOpacity,
                          label: metricLabel("CONCERT", "实音"), value: render.concertText)
                MetricBox(
                    theme: theme, glassOpacity: store.glassOpacity,
                    label: metricLabel("CENTS", "音分"),
                    value: render.centsDisplayText,
                    valueColor: render.isInTune ? theme.ok : theme.textPrimary
                )
                MetricBox(theme: theme, glassOpacity: store.glassOpacity,
                          label: metricLabel("FREQ", "频率"),
                          // 【專屬規範 S-1】無訊號時頻率格
                          // 顯示「—」，不留 0.0 Hz 假讀數。
                          value: viewModel.noSignal ? "—" : render.frequencyText)
            }

            PitchTraceView(
                samples: viewModel.traceSamples,
                tolerance: engine.settings.toleranceCents,
                frozen: render.stabilityFrozen,
                micActive: engine.isRunning,
                badgeText: render.stabilityBadgeText,
                theme: theme,
                pageVisible: pageVisible,
                onTap: { viewModel.toggleFreeze() })
                .frame(height: traceHeight)
        }
    }
}

/// 數據卡單格（返修批7・F6 抽出）：標籤恆靜態、值逐幀
/// 變；獨立 View 後逐幀差分只落值文字，玻璃盒身不重建。
/// 視覺參數與舊 metricBox 函數逐項一致。
private struct MetricBox: View {
    let theme: TunerTheme
    let glassOpacity: Int
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                         theme: theme, glassOpacity: glassOpacity)
    }
}


struct PitchTraceView: View {
    let samples: [(t: TimeInterval, cents: Double?)]
    let tolerance: Double
    let frozen: Bool
    let micActive: Bool
    let badgeText: String
    let theme: TunerTheme
    /// 頁面可見性（返修批7 F5）：切到節拍器頁後本頁不可見，
    /// 待機波 TimelineView 必須暫停，不再 25fps 空轉。
    var pageVisible: Bool = true
    let onTap: () -> Void

    private static let span: TimeInterval = 8.0
    private static let range: Double = 50

    /// 【返修批10】待機判定改以「麥克風未運行」為準
    /// （Laurent 指示：未開始時要有動畫）：舊制以樣本
    /// 池有無音分判定——停麥後舊樣本殘留令 hasSignal
    /// 恆真，待機波永不回來，畫面只剩靜止舊軌跡或空
    /// 卡。改：麥未開即待機動畫（凍結定格且有數據時
    /// 例外，保留定格軌跡供讀數）。
    private var hasSignal: Bool {
        micActive || (frozen && samples.contains { $0.cents != nil })
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if hasSignal {
                Canvas { ctx, size in drawTrace(in: &ctx, size: size) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 25.0, paused: !pageVisible)) { context in
                    Canvas { ctx, size in
                        drawIdle(in: &ctx, size: size,
                                 ts: context.date.timeIntervalSince1970)
                    }
                }
            }
            // 【返修批7 A1】字典鍵為全串『音高轨迹 · PITCH TRACE』，
            // 舊寫法查裸詞再手拼後綴永遠落空（zh-TW 亦顯示簡體）。
            Text(L10n.t("音高轨迹 · PITCH TRACE"))
                .font(.system(size: 8.5, weight: .bold))
                // 【五維審計・排版項16】CJK 段不施字距。
                .tracking(L10n.isCJK ? 0 : 0.7)
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
                                       : (theme.isDark
                                          ? Color.white.opacity(0.06)
                                          // 【五維審計・設計項11】淺色
                                          // 原為白 0.05（白底上近乎不
                                          // 可見）：改黑 0.05。
                                          : Color.black.opacity(0.05)),
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
        .accessibilityLabel(L10n.t("音高轨迹 · PITCH TRACE"))
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
        // 【返修批10】待機波可見度上調（填充 0.07→0.10、
        // 線 0.28→0.45）：舊值在實機近乎不可見，Laurent
        // 誤認無動畫；幅度呼吸（drawIdle 的 amp 調變）
        // 不變。
        ctx.fill(fill, with: .color(theme.accent.opacity(0.10)))
        ctx.stroke(line, with: .color(theme.accent.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}
#Preview {
    TunerView(engine: AudioEngine(), store: AppStore(), drone: DroneEngine())
}
