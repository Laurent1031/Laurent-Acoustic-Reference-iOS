import SwiftUI

/// 節拍器畫面（階段 3）：版面對照 Laurent 實機截圖與母本——
/// 提示列、預備拍／TAP 列、節拍圓點矩陣、大轉盤（BPM 里程表）＋
/// 豎直推子、步進鈕、速度預置橫滑列、bento 選項格、START 大鈕。
/// 【返修批10】選項改頁內玻璃選單：批9 的系統 Menu 彈出
/// 巨型玻璃面板遮擋大半屏、勾在左側，Laurent 點名「布
/// 局很丑」並指示勾放右邊——拍號／細分／音色／預設／漸
/// 速改頁內底部浮出面板，選中勾統一在行右。
/// 【返修批11】批10 面板實機再被否決（玻璃疊影、遮擋、
/// 「又难看又遮挡」），Laurent 定版「我要苹果原生的卡
/// 片」「全部都要苹果原生生态」：選單改系統原生 sheet
/// 卡片＋原生 List（見 panelSheet），勾仍在行右。
struct MetronomeView: View {
    @ObservedObject var engine: MetronomeEngine
    @ObservedObject var viewModel: MetronomeViewModel
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var breathing = false
    @State private var showEditor = false
    @State private var editorText = ""
    @State private var editorStartBpm = 0
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var showDeletePreset = false
    @State private var showCustomRamp = false
    @State private var showGrouping = false
    /// 【返修批11】選單開啟態（原生 sheet(item:) 呈現）。
    @State private var openPanel: MetroPanel?

    /// 選單種類（拍號／細分／音色／預設／漸速）。
    private enum MetroPanel: String, Equatable, Identifiable {
        case signature, subdivision, timbre, preset, ramp
        var id: String { rawValue }
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        GeometryReader { geo in
            // 【返修批2】整頁固定一屏、不捲動（Laurent 指示：
            // 「我要一整頁剛剛好，不要讓我往下拉」）。返修批1
            // 的 ScrollView 版面撤除：各列定高，舞台列以
            // maxHeight 吸收全部剩餘高度、錶盤尺寸隨之伸縮
            // （下限隨舞台高、上限 208；返修批7 起短屏另有
            // 緊湊級，見下）。附帶收益：推子／轉盤的
            // 拖動不再被捲動手勢半路取消——返修批1 實機
            // 「推桿中途數字卡在中間」正是捲動取消 onEnded、
            // 里程表凍結在小數位置；VM 另有看門狗雙保險。
            let contentWidth = geo.size.width - 32
            // 【返修批7・E2/E4】短屏緊湊級：各列定高收縮、
            // 間距收窄，把高度還給舞台；緊湊級下同開 BPM
            // 編輯列時再隱藏圓點列與預置列（E4）。
            // 【五維審計 F2／專屬規範 §0.2】門檻 640→660 與
            // 調音頁統一：舊制下 availH 642（X 級）不進緊湊
            // 級、編輯＋分組同開時舞台僅 57 而推子最小全高
            // 76，上下限籤溢出舞台壓鄰列；統一門檻後 X 級
            // 走緊湊軌、舞台 237，夾縫消失。
            let compact = geo.size.height < 660

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: compact ? 5 : 9) {
                    hintRow(theme: theme, compact: compact)
                    controlRow(theme: theme, compact: compact)
                    // 【五維審計 F7／專屬規範 §B.7】compact 級
                    // 編輯列移至控制列之下：原位（舞台之下）
                    // 在 SE 上底緣落入數字鍵盤區 ≈14pt；移位
                    // 後底緣螢幕 y ≈210、距鍵盤頂 >240pt，
                    // 結構性免疫。常規級維持舞台下原位。
                    if compact && showEditor {
                        editorRow(theme: theme)
                    }
                    if !(compact && showEditor) {
                        dotsRow(theme: theme, width: contentWidth,
                                compact: compact)
                    }
                    GeometryReader { stageGeo in
                        // 【返修批7・E2】錶盤下限改隨舞台可用
                        // 高：舊下限 120 在 SE 舞台僅 74pt 時
                        // 上下各溢出 ≈23pt 壓圓點／步進列。
                        // 【五維審計 F2／專屬規範 §B.4】下限
                        // 56→72，與推子最小全高（railH 下限
                        // 36＋上下籤 36）對齊——舊制兩下限間
                        // 的 56–76 夾區令推子繪出舞台框。
                        // 【專屬規範 §B.4/G3】寬裕級（availH
                        // ≥740）錶盤帽 208→248：大屏舞台原空
                        // 置 28% 環帶，帽隨級放寬。
                        let dialCap: CGFloat = geo.size.height >= 740 ? 248 : 208
                        let dialSize = min(dialCap, max(72, min(stageGeo.size.height,
                                                            contentWidth * 0.56)))
                        stageRow(theme: theme, dialSize: dialSize,
                                 railHeight: dialSize)
                            .frame(width: stageGeo.size.width,
                                   height: stageGeo.size.height)
                    }
                    .frame(maxHeight: .infinity)
                    steppersRow(theme: theme)
                    if showEditor && !compact { editorRow(theme: theme) }
                    if !(compact && showEditor) {
                        tempoPresetRow(theme: theme)
                    }
                    bentoGrid(theme: theme, compact: compact)
                    startButton(theme: theme, compact: compact)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)

            }
        }
        .onChange(of: engine.lastError) { _, error in
            if let error { viewModel.showToast(error) }
        }
        // 【返修批7・F11】離頁拆 link：VM.viewDidDisappear
        // 原無任何呼叫點（invalidate 死路徑），比照
        // TunerView 接上——殼層卸載時不留 runloop 殘留
        // 引用。雙頁保活下切頁不觸發本回調，可見性停啟
        // 由 setPageVisible 門控（ContentView 接線）。
        .onDisappear {
            viewModel.viewDidDisappear()
        }
        // 外接鍵盤（母本行 12152，階段 7 補齊）：↑↓ ±1、
        // PageUp／PageDown ±10 BPM。
        .metroKeyboardShortcuts(viewModel: viewModel)
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                Text(L10n.t(toast))
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
                    .padding(.bottom, 74)
                    .transition(.opacity)
                    // 【返修批2・按鍵審計】Toast 純顯示，關命中
                    // 測試避免吞掉底部區域的點按。
                    .allowsHitTesting(false)
            }
        }
        .alert(L10n.t("保存预设"), isPresented: $showSavePreset) {
            TextField(L10n.t("预设名称（如：练习曲 66）"), text: $presetName)
            Button(L10n.t("取消"), role: .cancel) {}
            Button(L10n.t("保存")) {
                if viewModel.savePreset(name: presetName) { presetName = "" }
            }
        }
        .confirmationDialog(L10n.t("删除当前预设？"), isPresented: $showDeletePreset,
                            titleVisibility: .visible) {
            Button(L10n.t("删除"), role: .destructive) { viewModel.deleteActiveUserPreset() }
            Button(L10n.t("取消"), role: .cancel) {}
        }
        .sheet(isPresented: $showCustomRamp) {
            CustomRampSheet(viewModel: viewModel, isPresented: $showCustomRamp)
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationBackground { theme.background }
        }
        .sheet(isPresented: $showGrouping) {
            GroupingSheet(viewModel: viewModel, isPresented: $showGrouping)
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationBackground { theme.background }
        }
        // 【返修批11・原生卡片】五格選單的系統 sheet（見
        // panelSheet）：系統材質卡片＋拖動指示器，拍號／
        // 預設項多給 .large 檔位。
        .sheet(item: $openPanel) { panel in
            panelSheet(panel, theme: theme)
                .preferredColorScheme(store.effectiveForcedColorScheme)
                .presentationDetents(panel == .signature || panel == .preset
                                     ? [.medium, .large] : [.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 提示列（母本 metroHint）

    private func hintRow(theme: TunerTheme, compact: Bool) -> some View {
        Text(viewModel.hintText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(viewModel.displayIsCountIn && viewModel.isPlaying
                             ? theme.sharp : theme.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 20 : 26)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.hintTapped() }
    }

    // MARK: - 預備拍／TAP 列

    private func controlRow(theme: TunerTheme, compact: Bool) -> some View {
        HStack {
            // 【返修批10・開關統一】Laurent 指示：預備拍
            // 按鈕要與震動／音效反饋開關一樣——改用與系
            // 統設置頁 feedbackGroup 完全相同的標準
            // Toggle 開關（51×31、accent tint），撤掉舊
            // 的自繪迷你開關膠囊（34×20 假開關嵌在按鈕
            // 裡，形制與全 App 開關不一致）。切換仍走
            // VM.toggleCountIn（震動 tap 8ms＋uiSound
            // tick 與其他開關同一套反饋，不變）。
            HStack(spacing: 8) {
                Text(L10n.t("预备拍"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityHidden(true)
                Toggle(isOn: Binding(
                    get: { viewModel.settings.countIn },
                    set: { newValue in
                        if newValue != viewModel.settings.countIn {
                            viewModel.toggleCountIn()
                        }
                    })) {
                    EmptyView()
                }
                .labelsHidden()
                .tint(theme.accent)
                .accessibilityLabel(L10n.t("预备拍"))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)

            Spacer()

            Button {
                viewModel.tapTempo()
            } label: {
                Text(L10n.t("TAP 测速"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 14)
                    // 【返修批10】與預備拍開關膠囊同高 36
                    // （標準開關 31 的容納高），整列齊平。
                    .frame(height: 36)
                    .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            }
            .buttonStyle(GlassPressButtonStyle())
        }
    }

    // MARK: - 節拍圓點矩陣（母本 renderBeatDots + strikePulse）

    private func dotsRow(theme: TunerTheme, width: CGFloat,
                         compact: Bool) -> some View {
        let count = max(1, viewModel.settings.beatsPerBar)
        let slot = width / CGFloat(count)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { pillar in
                // 【返修批7・F1】圓點抽成 BeatDotCell 獨立
                // View 單獨觀察脈衝（見該型別註解）；lvl／
                // isCurrent 為低頻值輸入、逐拍由本列重算帶入。
                BeatDotCell(
                    pillar: pillar,
                    lvl: pillar < viewModel.settings.beatAccents.count
                        ? viewModel.settings.beatAccents[pillar] : 1,
                    isCurrent: viewModel.currentPillar == pillar,
                    slot: slot, compact: compact,
                    theme: theme, glassOpacity: store.glassOpacity,
                    pulse: viewModel.pulseRender)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.cycleAccent(pillar: pillar) }
                    // 【返修批7・E8】拍柱格 VoiceOver 化：
                    // 此前純 onTapGesture、無 label/action，
                    // VoiceOver 用戶無法操作；整格併為單一
                    // 元素，標籤含拍序與重音等級，isButton
                    // ＋預設 action 與點按同一行為。
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dotAccessibilityLabel(pillar: pillar))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        viewModel.cycleAccent(pillar: pillar)
                    }
            }
        }
        .frame(height: compact ? 58 : 74)
    }

    /// 拍柱格無障礙標籤：「<拍序>，<重音等級>」（等級查表
    /// 與 BeatDotCell 同源 MetronomeSettings.levelLabels）。
    private func dotAccessibilityLabel(pillar: Int) -> String {
        let accents = viewModel.settings.beatAccents
        let lvl = pillar < accents.count ? accents[pillar] : 1
        return "\(pillar + 1)，\(L10n.t(MetronomeSettings.levelLabels[lvl]))"
    }

    /// 節拍圓點（返修批7・F1 抽出獨立 View）：原 dotCell
    /// 為本頁本體函數、讀 VM 脈衝值，脈衝以 120 Hz 寫入
    /// 時整頁 body 跟著重算。抽出後本 View 單獨觀察
    /// PulseRenderState，脈衝幀只重繪圓點本身；lvl／
    /// isCurrent／slot 等低頻輸入由 dotsRow 以值傳入。
    /// 視覺參數與舊 dotCell 逐項一致（光暈漸層、本體
    /// 樣式、縮放係數皆原樣搬移）。
    struct BeatDotCell: View {
        let pillar: Int
        let lvl: Int
        let isCurrent: Bool
        let slot: CGFloat
        let compact: Bool
        let theme: TunerTheme
        let glassOpacity: Int
        @ObservedObject var pulse: PulseRenderState

        var body: some View {
            let base: CGFloat = lvl == 3 ? 44 : lvl == 2 ? 40 : lvl == 1 ? 35 : 31
            let diameter = min(base, max(24, slot - 10))
            let p = isCurrent ? pulse.value : 0
            let sb: Double = lvl == 3 ? 0.14 : lvl == 2 ? 0.10 : 0.07
            // 亮起漸層走主題 token（補強段）：預備拍橙、強拍綠、
            // 其餘藍；樂池暗紅主題下三者全收斂為紅譜（見 TunerTheme）。
            let litColors: [Color] = pulse.isCountIn && isCurrent
                ? theme.countInGradient
                : (lvl == 3 ? theme.beatStrongGradient : theme.beatNormalGradient)
            return VStack(spacing: 3) {
                ZStack {
                    // 光暈（母本 ::before 的徑向柔光）：正圓、
                    // accent 色徑向漸層至全透明、隨脈衝放大。
                    // 【返修批2】舊版以 60×102 實心橢圓＋強拍綠
                    // 呈現，實機成一團橢圓綠暈（Laurent 點名
                    // 「外圍那圈不對」）；母本原式即徑向漸層，
                    // 改回漸層本體，顏色恆走 accent（預備拍走
                    // sharp 琥珀），不再用 ok 綠。
                    Circle()
                        .fill(RadialGradient(
                            colors: [(pulse.isCountIn
                                        ? theme.sharp : theme.accent)
                                .opacity(0.32 * p), Color.clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 34))
                        .frame(width: 68, height: 68)
                        .scaleEffect(0.85 + p * 0.3)
                        .allowsHitTesting(false)
                    // 本體（依等級的母本樣式）。
                    dotBody
                        .frame(width: diameter, height: diameter)
                        .overlay {
                            Circle()
                                .fill(LinearGradient(colors: litColors,
                                                     startPoint: .top, endPoint: .bottom))
                                .opacity(lvl > 0 ? p : 0)
                        }
                        .scaleEffect(1 + sb * p)
                    Text("\(pillar + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(lvl == 3 ? .white : theme.textSecondary)
                }
                .frame(height: compact ? 40 : 46)
                Text(L10n.t(MetronomeSettings.levelLabels[lvl]))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
        }

        @ViewBuilder
        private var dotBody: some View {
            switch lvl {
            case 3:
                Circle().fill(theme.accent)
                    .shadow(color: theme.accent.opacity(0.45), radius: 6, y: 2)
            case 2:
                Circle().fill(theme.accent.opacity(0.18))
                    .overlay { Circle().strokeBorder(theme.accent, lineWidth: 1.5) }
            case 1:
                // 純玻璃點：邊緣高光由 glassEffect 本體給出，
                // 不再手繪描邊（液態玻璃全量替換原則）。
                GlassSurface(shape: Circle(), theme: theme,
                             glassOpacity: glassOpacity)
            default:
                Circle()
                    .strokeBorder(Color(red: 128 / 255, green: 128 / 255, blue: 140 / 255,
                                        opacity: 0.5),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }

    // MARK: - 中央舞台：轉盤＋推子

    private func stageRow(theme: TunerTheme, dialSize: CGFloat,
                          railHeight: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Spacer(minLength: 0)
            BpmDialView(viewModel: viewModel, dial: viewModel.dial,
                        theme: theme, size: dialSize,
                        onTapNumber: openEditor)
            Spacer(minLength: 0)
            // 推子內縮（補強段）：頁面 .horizontal 16 ＋ 此處
            // trailing 8 = 軌道右緣距螢幕邊 24pt，離開 iOS
            // 邊緣返回手勢熱區（約 20pt）；視覺上推子僅左移
            // 8pt，刻度數字列隨之內移，其餘版面不動。
            BpmFaderView(viewModel: viewModel, dial: viewModel.dial,
                         theme: theme, height: railHeight,
                         glassOpacity: store.glassOpacity)
                .padding(.trailing, 8)
        }
    }

    /// 轉盤＋里程表（返修批3 抽出獨立 View）：觀察 VM 的
    /// 設定級狀態與 dial 渲染狀態；里程表 spring 幀只重繪
    /// 本 View、不牽動整頁（拖動卡頓修復的一半）。
    struct BpmDialView: View {
        @ObservedObject var viewModel: MetronomeViewModel
        @ObservedObject var dial: DialRenderState
        let theme: TunerTheme
        let size: CGFloat
        let onTapNumber: () -> Void

        var body: some View {
            let ratio = Double(viewModel.settings.bpm - MetronomeSettings.bpmMin)
                / Double(viewModel.settings.bpmMaxNow - MetronomeSettings.bpmMin)
            return ZStack {
                Circle()
                    .stroke(theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                            lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.001, ratio))
                    .stroke(theme.accent,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    odometer
                    Text("BPM")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(theme.textMuted)
                    Text(MetronomeSettings.tempoTerm(viewModel.settings.bpm))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            // 一般手勢（非 highPriority）：子層里程表的
            // numberDrag 優先——數字區走 numberDrag、其餘
            // 錶盤走 dialDrag（返修批2 按鍵審計定版）。
            .gesture(dialDrag)
        }

        /// BPM 里程表（母本 .bpm-num/.bpm-col：條帶兩圈
        /// 0–9、逐柱 spring；柱位經 dial 發布，目標恆整數）。
        private var odometer: some View {
            // 【返修批7・E2】字級下限 34→26：小錶盤（<113pt，
            // 僅短屏擠壓時出現）三位數字寬 ≈50 仍塞得進
            // 56pt 下限錶盤，不再溢出圓外。
            let fontSize = min(52, max(26, size * 0.30))
            let digitH = fontSize
            let digitW = fontSize * 0.62
            return HStack(spacing: 1) {
                odoColumn(index: 0, fontSize: fontSize, digitH: digitH)
                    .frame(width: dial.odoHundredsBlank ? 0 : digitW)
                    .opacity(dial.odoHundredsBlank ? 0 : 1)
                odoColumn(index: 1, fontSize: fontSize, digitH: digitH)
                    .frame(width: digitW)
                odoColumn(index: 2, fontSize: fontSize, digitH: digitH)
                    .frame(width: digitW)
            }
            .contentShape(Rectangle())
            .gesture(numberDrag)
        }

        private func odoColumn(index: Int, fontSize: CGFloat,
                               digitH: CGFloat) -> some View {
            let m = index < dial.odoPositions.count ? dial.odoPositions[index] : 0
        // 【裝機返修】舊版 frame(height:) 預設置中對齊，20 位
        // 長條被置中後可見窗對錯位、且 Text 行高大於 digitH
        // 使相鄰數字上下滲入（實機「013 疊 120」糊成一團）。
        // 改：逐格固定高＋逐格裁切、窗框頂對齊、offset 移位。
        return VStack(spacing: 0) {
            ForEach(0..<20, id: \.self) { i in
                Text("\(i % 10)")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .frame(height: digitH)
                    .clipped()
            }
        }
            .offset(y: -CGFloat(m) * digitH)
            .frame(height: digitH, alignment: .top)
            .clipped()
        }

        // MARK: - 手勢（轉盤豎拖／數字點按・橫 scrub・豎拖）

        @State private var dialStartBpm: Int?
        @State private var dialStartY: CGFloat = 0

        private var dialDrag: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // 自癒再武裝：上一拖被系統取消、看門狗已
                    // endAdjust 時 start 可能殘留；VM 不在
                    // adjusting 即視為新拖、重新取樣。
                    if dialStartBpm == nil || !viewModel.bpmAdjusting {
                        dialStartBpm = viewModel.settings.bpm
                        dialStartY = value.startLocation.y
                        viewModel.beginAdjust()
                    }
                    guard let start = dialStartBpm else { return }
                    let dy = dialStartY - value.location.y
                    viewModel.setBpmFromDrag(Double(start) + Double(dy) * 0.55)
                    viewModel.dragTickBpm(viewModel.settings.bpm)
                }
                .onEnded { _ in
                    dialStartBpm = nil
                    viewModel.endAdjust()
                }
        }

        private enum NumberDragMode { case undecided, scrub, dial }
        @State private var numStartBpm: Int?
        @State private var numStartTime: Date?
        @State private var numMode: NumberDragMode = .undecided

        private var numberDrag: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if numStartBpm == nil || !viewModel.bpmAdjusting {
                        numStartBpm = viewModel.settings.bpm
                        numStartTime = value.time
                        numMode = .undecided
                        viewModel.beginAdjust()
                    }
                    guard let start = numStartBpm else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if numMode == .undecided && max(abs(dx), abs(dy)) > 9 {
                        numMode = abs(dx) > abs(dy) ? .scrub : .dial
                    }
                    switch numMode {
                    case .scrub:
                        viewModel.setBpmFromDrag(Double(start) + Double(dx) * 0.25)
                    case .dial:
                        viewModel.setBpmFromDrag(Double(start) + Double(-dy) * 0.55)
                    case .undecided:
                        break
                    }
                    if numMode != .undecided {
                        viewModel.dragTickBpm(viewModel.settings.bpm)
                    }
                }
                .onEnded { value in
                    let quick = numStartTime.map { value.time.timeIntervalSince($0) < 0.4 } ?? false
                    let wasTap = numMode == .undecided && quick
                    numStartBpm = nil
                    numMode = .undecided
                    viewModel.endAdjust()
                    if wasTap { onTapNumber() }
                }
        }
    }

    // MARK: - 推子（母本 .fader：相對拖動、吸附、橡皮筋、spring 填充）

    /// 推子（返修批3 抽出獨立 View）：填充比經 dial 發布，
    /// 拖動幀只重繪本 View（拖動卡頓修復的另一半）。
    struct BpmFaderView: View {
        @ObservedObject var viewModel: MetronomeViewModel
        @ObservedObject var dial: DialRenderState
        let theme: TunerTheme
        let height: CGFloat
        /// 玻璃不透明度（五維審計・設計項7）：軌道玻璃改走
        /// theme.glass() 令牌公式，與全 App 同步受設定驅動。
        let glassOpacity: Int
        @State private var faderRubber: Double = 0

        var body: some View {
        // 母本推子是 iOS 控制中心式膠囊（.bpm-fader-rail）：
        // 全圓膠囊軌（寬 57）、上下限籤在軌的上下同軸、亮
        // 填充自底升起＋深度內影、字形隨填充覆蓋變色。
        // 【返修批7・E2】軌高下限 76→40：短屏小錶盤時
        // 推子全高（railH＋上下籤 36）不再反超舞台高。
        // 【五維審計 F2】下限再 40→36：推子最小全高 72
        // 與錶盤下限 72 對齊（專屬規範 §B.4/B.5）；全高
        // ＝max(72, height)，height ≥76 時與舊式逐值相同。
        let railH = max(36, height - 36)
        let fillH = max(14, railH * CGFloat(dial.faderRatio))
        let glyphCovered = fillH > 23
        let adjusting = faderStartBpm != nil
        let rubber = min(faderRubber, 60)
        let sx = 1 + (rubber / 60) * 0.07
        let sy = 1 + (rubber / 60) * 0.025
        let dark = theme.isDark
        return VStack(spacing: 4) {
            Text("\(viewModel.settings.bpmMaxNow)")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(theme.textSecondary)
                .frame(height: 14)

            ZStack(alignment: .bottom) {
                // 【液態玻璃全量替換】軌道改系統真玻璃：
                // 【五維審計・設計項7】tint 改走 theme.glass()
                // 令牌公式（原自帶白 0.14／灰 0.16 常數、不
                // 吃「玻璃不透明度」設定，是全 App 唯一脫離
                // 令牌的玻璃面）；折射與邊緣高光由本體給出。
                Capsule()
                    .fill(.clear)
                    .glassEffect(theme.glass(glassOpacity),
                                 in: Capsule())
                    // 【返修批9】與組件系統同款漸變高光描邊
                    // （規範一），推子軌的鏡面邊。
                    .overlay {
                        Capsule().strokeBorder(theme.glassStrokeGradient,
                                               lineWidth: 1)
                    }

                // 亮填充（母本 .bpm-fader-fill）：頂邊平直、
                // 底部隨膠囊裁切；漸層白為主、底緣淡藍灰，
                // 深度靠三層內影（頂緣高光／頂內側陰影／
                // 底緣藍調）。
                Rectangle()
                    .fill(LinearGradient(
                        colors: theme.faderFillColors,
                        startPoint: .top, endPoint: .bottom))
                    .frame(height: fillH)
                    .overlay(alignment: .top) {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.white)
                                .frame(height: 1)
                            LinearGradient(
                                colors: [Color.black.opacity(0.16), .clear],
                                startPoint: .top, endPoint: .bottom)
                                .frame(height: 12)
                            Spacer(minLength: 0)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, Color(hex: 0x0A3C8C).opacity(0.10)],
                            startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                    }
                    .shadow(color: .black.opacity(dark ? 0 : 0.06),
                            radius: 6, x: 0, y: -2)

                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(glyphCovered ? theme.faderGlyphCovered
                                     : theme.faderGlyphUncovered)
                    .padding(.bottom, 12)
            }
            .frame(width: 57, height: railH)
            .clipShape(Capsule())
            // 【五維審計・設計項5】外層手繪平色描邊（白
            // 0.26／黑 0.06）刪除：與軌內批9 漸變描邊構成
            // 雙重描邊、平色圈蓋住漸變；描邊以漸變為唯一
            // 真源（軌的 .clipShape 後漸變描邊在軌緣內側）。
            .shadow(color: .black.opacity(adjusting ? 0.42 : (dark ? 0.28 : 0.10)),
                    radius: adjusting ? 22 : 15, x: 0, y: adjusting ? 20 : 12)
            .brightness(adjusting ? 0.05 : 0)
            .scaleEffect(x: sx, y: sy)

            Text("\(MetronomeSettings.bpmMin)")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(theme.textSecondary)
                .frame(height: 14)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(faderDrag(railHeight: railH))
        }

        @State private var faderStartBpm: Double?
        @State private var faderStartY: CGFloat = 0
        @State private var faderSnapped: Int?

        private func faderDrag(railHeight: CGFloat) -> some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if faderStartBpm == nil || !viewModel.bpmAdjusting {
                        faderStartBpm = Double(viewModel.settings.bpm)
                        faderStartY = value.startLocation.y
                        faderSnapped = nil
                        viewModel.beginAdjust()
                    }
                    guard let start = faderStartBpm else { return }
                    let maxNow = Double(viewModel.settings.bpmMaxNow)
                    let range = maxNow - Double(MetronomeSettings.bpmMin)
                    var target = start + Double(faderStartY - value.location.y)
                        / Double(railHeight) * range
                    // 超界量給橡皮筋（母本：rail 依超界縮放、
                    // 值本身鉗制）。
                    if target < Double(MetronomeSettings.bpmMin) {
                        faderRubber = Double(MetronomeSettings.bpmMin) - target
                        target = Double(MetronomeSettings.bpmMin)
                    } else if target > maxNow {
                        faderRubber = target - maxNow
                        target = maxNow
                    } else {
                        faderRubber = 0
                    }
                    var snappedNow: Int?
                    for point in MetronomeSettings.faderSnapPoints
                    where abs(target - Double(point)) <= 1.5 {
                        target = Double(point)
                        snappedNow = point
                    }
                    if let snappedNow, snappedNow != faderSnapped {
                        HapticsEngine.shared.tap(milliseconds: 8)
                    }
                    faderSnapped = snappedNow
                    viewModel.setBpmFromDrag(target)
                    viewModel.dragTickBpm(viewModel.settings.bpm)
                }
                .onEnded { _ in
                    faderStartBpm = nil
                    faderRubber = 0
                    viewModel.endAdjust()
                    HapticsEngine.shared.tap(milliseconds: 8)
                }
        }
    }

    // MARK: - 步進鈕與編輯器

    private func steppersRow(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            MetronomeHoldRepeatButton(title: "−5", theme: theme, glassOpacity: store.glassOpacity) { viewModel.stepBpm(-5) }
            MetronomeHoldRepeatButton(title: "−1", theme: theme, glassOpacity: store.glassOpacity) { viewModel.stepBpm(-1) }
            MetronomeHoldRepeatButton(title: "+1", theme: theme, glassOpacity: store.glassOpacity) { viewModel.stepBpm(1) }
            MetronomeHoldRepeatButton(title: "+5", theme: theme, glassOpacity: store.glassOpacity) { viewModel.stepBpm(5) }
        }
    }

    private func editorRow(theme: TunerTheme) -> some View {
        HStack(spacing: 8) {
            TextField("BPM", text: $editorText)
                .keyboardType(.numberPad)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(width: 90)
                .padding(.vertical, 8)
                .glassBackground(in: RoundedRectangle(cornerRadius: 10, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
            Text("BPM")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textMuted)
            Spacer()
            Button(L10n.t("取消")) { showEditor = false }
                .buttonStyle(GlassPressButtonStyle())
                .foregroundStyle(theme.textSecondary)
            Button(L10n.t("确定")) { commitEditor() }
                .buttonStyle(GlassPressButtonStyle())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.accent)
        }
    }

    /// 母本 commit 防呆：編輯期間 BPM 被其他控件改過且輸入未動
    /// （文字與開啟時相同）→ 只關閉、不覆寫（行 10874）。
    private func commitEditor() {
        defer { showEditor = false }
        let untouched = editorText == String(editorStartBpm)
        if untouched && viewModel.settings.bpm != editorStartBpm { return }
        if let value = Int(editorText.trimmingCharacters(in: .whitespaces)) {
            viewModel.setBpm(value)
        } else {
            // 輸入無法解析（審計修復）：此前靜默關閉、不套用
            // 也不提示，與「按了沒反應」同類；改以 Toast 明示。
            viewModel.showToast("请输入有效的 BPM 数字")
        }
    }

    private func openEditor() {
        editorText = String(viewModel.settings.bpm)
        editorStartBpm = viewModel.settings.bpm
        showEditor = true
    }

    // MARK: - 速度預置列

    private func tempoPresetRow(theme: TunerTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(MetronomeSettings.tempoPresets.enumerated()),
                        id: \.offset) { _, preset in
                    let active = viewModel.settings.bpm == preset.bpm
                    Button {
                        viewModel.setBpm(preset.bpm)
                    } label: {
                        Text(L10n.t("\(preset.name) \(preset.bpm)"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 13)
                            .frame(height: 32)
                            .background {
                                GlassChipBackground(selected: active, theme: theme,
                                                    glassOpacity: store.glassOpacity)
                            }
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
        }
    }

    // MARK: - Bento 選項格（母本 bento：拍號／細分／音色＋預設／漸速）

    private func bentoGrid(theme: TunerTheme, compact: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                sigTile(theme: theme, compact: compact)
                // 【返修批11】細分／音色／預設／漸速的選項
                // 本體移入原生 sheet 卡片（panelSheet），
                // 格位只剩開關鈕。
                menuTile(theme: theme, compact: compact, title: L10n.t("细分"),
                         value: L10n.t(MetronomeSettings.subdivisionOptions
                            .first { $0.value == viewModel.settings.subdivision }?.label ?? ""),
                         panel: .subdivision)
                menuTile(theme: theme, compact: compact, title: L10n.t("音色"),
                         value: viewModel.settings.timbre.displayName,
                         panel: .timbre)
            }
            // 補強段第二列：不規則拍分組（僅適用拍號顯示）。
            // 【返修批2】Gap Click 靜音小節經 Laurent 指示
            // 整項去掉（格、面板、引擎行為全撤；模型欄位
            // 保留供舊存檔／備份解碼相容，恆不生效）。
            if viewModel.settings.groupingAvailable {
                HStack(spacing: 8) {
                    Button {
                        showGrouping = true
                    } label: {
                        tileLabel(theme: theme, compact: compact, title: L10n.t("重音分组"),
                                  value: viewModel.currentGrouping
                                    .map(String.init).joined(separator: "+"))
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    Spacer(minLength: 0)
                }
            }
            wideMenuRow(theme: theme, compact: compact, title: L10n.t("预设"),
                        value: viewModel.activePreset.map {
                            $0.builtin ? L10n.t($0.name) : $0.name
                        } ?? L10n.t("选择"),
                        panel: .preset)
            wideMenuRow(theme: theme, compact: compact, title: L10n.t("渐速"),
                        value: viewModel.rampState.active
                            ? "\(viewModel.rampState.from) → \(viewModel.rampState.to)"
                            : L10n.t("关闭"),
                        panel: .ramp)
        }
    }

    /// 開啟原生選單卡片（輕震與分段切換同級）。
    private func presentPanel(_ panel: MetroPanel) {
        openPanel = panel
        HapticsEngine.shared.tap(milliseconds: 4)
    }

    /// 關卡後續動作（保存／刪除預設、自訂漸速表單）：
    /// sheet 收起動畫期間再呈現 alert／sheet 會被系統
    /// 丟棄，延 0.45 s 待收起完成才觸發。
    private func closePanel(then action: @escaping () -> Void) {
        openPanel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            action()
        }
    }

    /// 漸速 Menu 勾選態（審計修復）：此前 checked 恆 false、
    /// 永不標示作用中方案。RampState 不存方案 id，以運行參數
    /// （step／每步小節／方向）反推：快速方案全匹配者為作用
    /// 中；自訂＝進行中且無快速方案匹配；關閉＝未進行。
    private func rampSchemeChecked(_ scheme: RampQuickScheme) -> Bool {
        let r = viewModel.rampState
        switch scheme.id {
        case "off":
            return !r.active
        case "custom":
            guard r.active else { return false }
            return !RampQuickScheme.all.contains { s in
                guard let d = s.delta else { return false }
                return s.step == r.step && s.bars == r.barsPerStep
                    && (d > 0) == (r.to > r.from)
            }
        default:
            guard let d = scheme.delta, r.active else { return false }
            return scheme.step == r.step && scheme.bars == r.barsPerStep
                && (d > 0) == (r.to > r.from)
        }
    }

    private func sigTile(theme: TunerTheme, compact: Bool) -> some View {
        let s = viewModel.settings
        let value = "\(s.beatsPerBar)/\(s.beatUnit)" + (s.isDottedBeat ? " ♩." : "")
        return ZStack(alignment: .topTrailing) {
            // 【返修批11】改原生 sheet 卡片開關鈕（見 panelSheet）。
            Button {
                presentPanel(.signature)
            } label: {
                tileLabel(theme: theme, compact: compact, title: L10n.t("拍号"), value: value)
            }
            .buttonStyle(GlassPressButtonStyle())
            Button {
                viewModel.resetAccents()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    // 【五維審計 F9／專屬規範 §E.3】命中
                    // 24→32：字形不變、框擴大可點。
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel(L10n.t("重置重音"))
        }
    }

    /// 【返修批11】格位鈕：點按開啟對應的原生選單卡片，
    /// 外觀與舊 label 逐項一致。
    private func menuTile(theme: TunerTheme, compact: Bool,
                          title: String, value: String,
                          panel: MetroPanel) -> some View {
        Button {
            presentPanel(panel)
        } label: {
            tileLabel(theme: theme, compact: compact, title: title, value: value)
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    /// 【返修批11】寬列鈕，同 menuTile。
    private func wideMenuRow(theme: TunerTheme, compact: Bool,
                             title: String, value: String,
                             panel: MetroPanel) -> some View {
        Button {
            presentPanel(panel)
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: compact ? 38 : 42)
            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private func tileLabel(theme: TunerTheme, compact: Bool,
                           title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textMuted)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 6 : 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 原生選單卡片（返修批11）

    /// 卡片標題（與格位標題同串）。
    private func panelTitle(_ panel: MetroPanel) -> String {
        switch panel {
        case .signature: return L10n.t("拍号")
        case .subdivision: return L10n.t("细分")
        case .timbre: return L10n.t("音色")
        case .preset: return L10n.t("预设")
        case .ramp: return L10n.t("渐速")
        }
    }

    /// 【返修批11・蘋果原生卡片】系統 sheet 內容：原生
    /// NavigationStack＋List（系統材質、原生行高與分隔
    /// 線、insetGrouped 卡片分區），右上「完成」鈕、亦
    /// 可下滑收起。取代批10 自製玻璃面板——其玻璃把底
    /// 層內容折射疊進卡內（實機截圖：預設／漸速行與
    /// START 鈕全疊影），Laurent 點名「又难看又遮挡」，
    /// 定版全原生生態。
    private func panelSheet(_ panel: MetroPanel, theme: TunerTheme) -> some View {
        NavigationStack {
            List {
                panelListContent(panel, theme: theme)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(panelTitle(panel))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("完成")) { openPanel = nil }
                }
            }
        }
    }

    /// 原生選項行：文字左、勾右（選中才顯示，accent 色
    /// 粗勾，與 iOS 設置的選擇列同形）；destructive 行
    /// 走系統紅。
    private func sheetRow(theme: TunerTheme, title: String, checked: Bool,
                          destructive: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(destructive ? Color.red : theme.textPrimary)
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

    @ViewBuilder
    private func panelListContent(_ panel: MetroPanel, theme: TunerTheme) -> some View {
        let s = viewModel.settings
        switch panel {
        case .signature:
            // 拍號 11 項原生單欄列（卡片可上滑至 .large，
            // 不再用自製兩欄格）；附點計拍獨立分區。
            Section {
                ForEach(Array(MetronomeSettings.signatures.enumerated()),
                        id: \.offset) { _, sig in
                    sheetRow(theme: theme, title: "\(sig.beats)/\(sig.unit)",
                             checked: s.beatsPerBar == sig.beats
                                && s.beatUnit == sig.unit) {
                        viewModel.setSignature(beats: sig.beats, unit: sig.unit)
                        openPanel = nil
                    }
                }
            }
            Section {
                sheetRow(theme: theme, title: L10n.t("附点计拍 (♩.)"),
                         checked: s.dottedBeat) {
                    viewModel.setDottedBeat(!s.dottedBeat)
                    openPanel = nil
                }
            }
        case .subdivision:
            Section {
                ForEach(Array(MetronomeSettings.subdivisionOptions.enumerated()),
                        id: \.offset) { _, option in
                    sheetRow(theme: theme, title: L10n.t(option.label),
                             checked: s.subdivision == option.value) {
                        viewModel.setSubdivision(option.value)
                        openPanel = nil
                    }
                }
            }
        case .timbre:
            Section {
                ForEach(MetronomeTimbre.allCases, id: \.self) { timbre in
                    sheetRow(theme: theme, title: timbre.displayName,
                             checked: s.timbre == timbre) {
                        viewModel.setTimbre(timbre)
                        openPanel = nil
                    }
                }
            }
        case .preset:
            Section(L10n.t("内建")) {
                ForEach(MetronomePreset.builtins) { preset in
                    sheetRow(theme: theme, title: L10n.t(preset.name),
                             checked: viewModel.activePresetId == preset.id) {
                        viewModel.applyPreset(preset)
                        openPanel = nil
                    }
                }
            }
            if !viewModel.userPresets.isEmpty {
                Section(L10n.t("自订")) {
                    ForEach(viewModel.userPresets) { preset in
                        sheetRow(theme: theme, title: preset.name,
                                 checked: viewModel.activePresetId == preset.id) {
                            viewModel.applyPreset(preset)
                            openPanel = nil
                        }
                    }
                }
            }
            Section {
                sheetRow(theme: theme, title: L10n.t("保存当前为预设"),
                         checked: false) {
                    closePanel { showSavePreset = true }
                }
                if let active = viewModel.activePreset, !active.builtin {
                    sheetRow(theme: theme, title: L10n.t("删除当前预设"),
                             checked: false, destructive: true) {
                        closePanel { showDeletePreset = true }
                    }
                }
            }
        case .ramp:
            Section {
                ForEach(RampQuickScheme.all) { scheme in
                    sheetRow(theme: theme, title: L10n.t(scheme.label),
                             checked: rampSchemeChecked(scheme)) {
                        let opensCustom = viewModel.applyRampQuick(scheme)
                        if opensCustom {
                            closePanel { showCustomRamp = true }
                        } else {
                            openPanel = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - START 主鈕（母本 btnToggleMetro：運行中 brightness 呼吸）

    private func startButton(theme: TunerTheme, compact: Bool) -> some View {
        Button {
            viewModel.togglePlay()
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.accent)
                if viewModel.isPlaying && viewModel.rampState.active {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: g.size.width * viewModel.rampState.progress)
                    }
                }
                Text(viewModel.isPlaying ? L10n.t("停止节拍器 · STOP") : L10n.t("启动节拍器 · START"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: compact ? 46 : 52)
            .brightness(viewModel.isPlaying && breathing ? 0.09 : 0)
        }
        .buttonStyle(GlassPressButtonStyle())
        .onChange(of: viewModel.isPlaying) { _, playing in
            // 母本 metroRunBreathe：1.5 s ease-in-out 往復，僅運行中。
            // 以 withAnimation 啟停，避免 repeatForever 在回程殘留。
            if playing {
                withAnimation(.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)) {
                    breathing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    breathing = false
                }
            }
        }
    }
}

/// 長按連調的時序協調（@MainActor 類別，避免在 View 結構內以
/// @Sendable 閉包捕獲狀態）：按下 340 ms 後首發、其後每 62 ms
/// 一次；340 ms 內抬手 → 由 pressEnded 補發一次普通點按
/// （母本 addHoldRepeat 的 click 吞吐語義）。
@MainActor
private final class HoldRepeater: ObservableObject {
    private var task: Task<Void, Never>?
    private var generation = 0
    private var fired = false
    /// 按壓中（供按壓亮斑回饋，母本 .glass-press）。
    @Published private(set) var isPressing = false

    func pressBegan(action: @escaping () -> Void) {
        guard task == nil else { return }
        isPressing = true
        fired = false
        generation += 1
        let gen = generation
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 340_000_000)
                // 【全邏輯複查・低】同 Features/HoldRepeater
                // 的 340 ms 邊界競態修復：睡醒先驗取消，防
                // pressEnded 先行補發後續行再發（雙發一步）。
                guard !Task.isCancelled else { return }
                self?.fired = true
                action()
                // 【返修批2・按鍵審計】連調上限 500 發
                // （≈31 s）：pressing(false) 若因手勢取消
                // 未送達，連調不致無限持續。
                for _ in 0..<500 {
                    try await Task.sleep(nanoseconds: 62_000_000)
                    guard !Task.isCancelled else { return }
                    action()
                }
            } catch {
                // 已取消（手指抬起）：結束連調。
            }
            // 自然跑完時自清（審計修復）：完成路徑此前不清
            // task，若 pressing(false) 又未送達，pressBegan 的
            // guard 會令此鈕在 View 生命週期內永久無反應。
            // 以代次比對防誤清後繼按壓的 Task。
            if let self, self.generation == gen { self.task = nil }
        }
    }

    func pressEnded(action: () -> Void) {
        isPressing = false
        task?.cancel()
        task = nil
        if !fired { action() }
        fired = false
    }
}

/// 長按連調步進鈕（母本 addHoldRepeat）。
private struct MetronomeHoldRepeatButton: View {
    let title: String
    let theme: TunerTheme
    let glassOpacity: Int
    let action: () -> Void
    @StateObject private var repeater = HoldRepeater()

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous), theme: theme, glassOpacity: glassOpacity)
            .brightness(repeater.isPressing ? 0.10 : 0)
            .animation(.easeOut(duration: 0.25), value: repeater.isPressing)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // 【對照母本審計】改用系統長按識別器的 pressing
            // 回調驅動連調：舊版 DragGesture(minimumDistance: 0)
            // 在實機上長按不觸發連調（Laurent 點名）；pressing
            // 於觸下即回 true、抬手回 false，與 HoldRepeater
            // 的 340/62 時序正好對接，單擊由 pressEnded 補發。
            .onLongPressGesture(minimumDuration: 0.34, maximumDistance: 12,
                                pressing: { pressing in
                                    if pressing {
                                        repeater.pressBegan(action: action)
                                    } else {
                                        repeater.pressEnded(action: action)
                                    }
                                },
                                perform: {})
            .accessibilityAddTraits(.isButton)
    }
}

/// 自訂漸速面板（母本漸速 popover 的自訂段：from/to/每N小節/±step）。
private struct CustomRampSheet: View {
    @ObservedObject var viewModel: MetronomeViewModel
    @Binding var isPresented: Bool
    @State private var fromText = ""
    @State private var toText = ""
    @State private var barsText = "4"
    @State private var stepText = "2"
    /// 驗證失敗的面板內提示（審計修復）：此前失敗只觸發主頁
    /// Toast，而 sheet 蓋在主頁之上、Toast 不可見，實機表現
    /// 為「按了沒反應」；改面板內直接顯示錯誤。
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("渐速参数")) {
                    LabeledContent(L10n.t("起始 BPM")) {
                        TextField("20–\(viewModel.settings.bpmMaxNow)", text: $fromText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(L10n.t("目标 BPM")) {
                        TextField("20–\(viewModel.settings.bpmMaxNow)", text: $toText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(L10n.t("每几小节")) {
                        TextField("1–32", text: $barsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(L10n.t("每次增减")) {
                        TextField("1–20", text: $stepText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if viewModel.rampState.active {
                    Section {
                        LabeledContent(L10n.t("进行中"),
                                       value: "\(viewModel.rampState.from) → \(viewModel.rampState.to) BPM")
                        Button(L10n.t("停止渐速"), role: .destructive) {
                            viewModel.stopRamp()
                        }
                    }
                }
                if showError {
                    Section {
                        Text(L10n.t("请检查渐速参数"))
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button(L10n.t("开始渐速")) {
                        let from = Int(fromText) ?? -1
                        let to = Int(toText) ?? -1
                        let bars = Int(barsText) ?? -1
                        let step = Int(stepText) ?? -1
                        if viewModel.startCustomRamp(from: from, to: to,
                                                     bars: bars, step: step) {
                            isPresented = false
                        } else {
                            showError = true
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("自定义渐速"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("关闭")) { isPresented = false }
                }
            }
            .onAppear {
                if fromText.isEmpty {
                    fromText = String(viewModel.settings.bpm)
                    toText = String(viewModel.settings.clampedBpm(viewModel.settings.bpm + 20))
                }
            }
            .onChange(of: fromText) { _, _ in showError = false }
            .onChange(of: toText) { _, _ in showError = false }
            .onChange(of: barsText) { _, _ in showError = false }
            .onChange(of: stepText) { _, _ in showError = false }
        }
        .presentationDetents([.medium])
    }
}

/// 不規則拍分組面板（補強段）：預置單選＋自訂編輯器。
/// 分組驅動重音型（組首第一組＝強、其餘組首＝次強、組內＝弱），
/// 拍點圓點與觸感分級皆由重音型決定，故套用分組即全鏈生效。
/// 首項預置恆為母本預設分組，其推導重音與母本預設逐值相等。
private struct GroupingSheet: View {
    @ObservedObject var viewModel: MetronomeViewModel
    @Binding var isPresented: Bool
    @State private var draft: [Int] = []

    private var beats: Int { viewModel.settings.beatsPerBar }
    private var presets: [[Int]] {
        MetronomeSettings.groupingPresets(beats: viewModel.settings.beatsPerBar,
                                          unit: viewModel.settings.beatUnit)
    }
    private var draftSum: Int { draft.reduce(0, +) }
    private var draftValid: Bool {
        !draft.isEmpty && draftSum == beats && draft.allSatisfy { $0 >= 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("预置分组") + "（\(viewModel.settings.currentSignatureKey)）") {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                        Button {
                            viewModel.setGrouping(preset)
                        } label: {
                            HStack {
                                Text(preset.map(String.init).joined(separator: " + "))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.currentGrouping == preset
                                    && viewModel.accentsMatchGrouping {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                Section {
                    LabeledContent(L10n.t("当前分组"),
                                   value: viewModel.currentGrouping
                                    .map(String.init).joined(separator: " + "))
                    if !viewModel.accentsMatchGrouping {
                        Text(L10n.t("目前重音含手动调整（点按拍柱改过），与分组推导不完全一致；套用任一分组将重写重音。"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.t("清除分组 · 回默认重音")) {
                        viewModel.clearGrouping()
                    }
                }
                Section(L10n.t("自定义分组")) {
                    ForEach(Array(draft.enumerated()), id: \.offset) { index, _ in
                        Stepper(value: draftBinding(index), in: 1...beats) {
                            Text(String(format: L10n.t("第 %d 组 · %d 拍"),
                                        index + 1, draft[index]))
                        }
                    }
                    .onDelete { draft.remove(atOffsets: $0) }
                    Button(L10n.t("新增一组")) {
                        draft.append(1)
                    }
                    .disabled(draftSum >= beats)
                    LabeledContent(L10n.t("合计"), value: "\(draftSum) / \(beats)")
                    Button(L10n.t("套用自定义分组")) {
                        viewModel.setGrouping(draft)
                    }
                    .disabled(!draftValid)
                }
            }
            .navigationTitle(L10n.t("重音分组"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("关闭")) { isPresented = false }
                }
            }
            .onAppear {
                if draft.isEmpty { draft = viewModel.currentGrouping }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func draftBinding(_ index: Int) -> Binding<Int> {
        Binding(get: { index < draft.count ? draft[index] : 1 },
                set: { if index < draft.count { draft[index] = $0 } })
    }
}


// MARK: - 外接鍵盤快捷鍵（母本行 12152）

/// 【返修批2・按鍵審計補回】本修飾器的定義原置於
/// DualModeView.swift，同屏功能取消刪檔時一併遺失、
/// 呼叫點懸空（現行樹編譯必敗）——就地補回：↑↓ ±1、
/// PageUp／PageDown ±10 BPM（母本鍵位原義）。
private struct MetroKeyboardShortcuts: ViewModifier {
    let viewModel: MetronomeViewModel

    func body(content: Content) -> some View {
        content
            .focusable()
            .onKeyPress(.upArrow) {
                viewModel.stepBpm(1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.stepBpm(-1)
                return .handled
            }
            .onKeyPress(.pageUp) {
                viewModel.stepBpm(10)
                return .handled
            }
            .onKeyPress(.pageDown) {
                viewModel.stepBpm(-10)
                return .handled
            }
    }
}

extension View {
    func metroKeyboardShortcuts(viewModel: MetronomeViewModel) -> some View {
        modifier(MetroKeyboardShortcuts(viewModel: viewModel))
    }
}
