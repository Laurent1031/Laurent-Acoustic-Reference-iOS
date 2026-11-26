import SwiftUI

/// 節拍器畫面（階段 3）：版面對照 Laurent 實機截圖與母本——
/// 提示列、預備拍／TAP 列、節拍圓點矩陣、大轉盤（BPM 里程表）＋
/// 豎直推子、步進鈕、速度預置橫滑列、bento 選項格、START 大鈕。
/// 選項以 SwiftUI Menu 呈現：母本在 iOS 上本就回退系統原生
/// select（updateSegUI 的 IS_IOS 分支），原生 Menu 為忠實等價。
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
    @State private var faderRubber: Double = 0

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        GeometryReader { geo in
            // 【返修批2】整頁固定一屏、不捲動（Laurent 指示：
            // 「我要一整頁剛剛好，不要讓我往下拉」）。返修批1
            // 的 ScrollView 版面撤除：各列定高，舞台列以
            // maxHeight 吸收全部剩餘高度、錶盤尺寸隨之伸縮
            // （下限 120、上限 208）。附帶收益：推子／轉盤的
            // 拖動不再被捲動手勢半路取消——返修批1 實機
            // 「推桿中途數字卡在中間」正是捲動取消 onEnded、
            // 里程表凍結在小數位置；VM 另有看門狗雙保險。
            let contentWidth = geo.size.width - 32

            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 9) {
                    hintRow(theme: theme)
                    controlRow(theme: theme)
                    dotsRow(theme: theme, width: contentWidth)
                    GeometryReader { stageGeo in
                        let dialSize = min(208, max(120, min(stageGeo.size.height,
                                                             contentWidth * 0.56)))
                        stageRow(theme: theme, dialSize: dialSize,
                                 railHeight: dialSize)
                            .frame(width: stageGeo.size.width,
                                   height: stageGeo.size.height)
                    }
                    .frame(maxHeight: .infinity)
                    steppersRow(theme: theme)
                    if showEditor { editorRow(theme: theme) }
                    tempoPresetRow(theme: theme)
                    bentoGrid(theme: theme)
                    startButton(theme: theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: engine.lastError) { _, error in
            if let error { viewModel.showToast(error) }
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
    }

    // MARK: - 提示列（母本 metroHint）

    private func hintRow(theme: TunerTheme) -> some View {
        Text(viewModel.hintText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(viewModel.displayIsCountIn && viewModel.isPlaying
                             ? theme.sharp : theme.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
            .onTapGesture { viewModel.hintTapped() }
    }

    // MARK: - 預備拍／TAP 列

    private func controlRow(theme: TunerTheme) -> some View {
        HStack {
            Button {
                viewModel.toggleCountIn()
            } label: {
                HStack(spacing: 7) {
                    Text(L10n.t("预备拍"))
                        .font(.system(size: 13, weight: .semibold))
                    ZStack(alignment: viewModel.settings.countIn ? .trailing : .leading) {
                        Capsule()
                            .fill(viewModel.settings.countIn
                                  ? theme.accent : Color.gray.opacity(0.35))
                            .frame(width: 34, height: 20)
                        Circle()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                            .padding(2)
                    }
                }
                .foregroundStyle(viewModel.settings.countIn ? .white : theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background {
                    if viewModel.settings.countIn {
                        Capsule().fill(theme.accent)
                    } else {
                        GlassSurface(shape: Capsule(), theme: theme,
                                     glassOpacity: store.glassOpacity)
                    }
                }
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer()

            Button {
                viewModel.tapTempo()
            } label: {
                Text(L10n.t("TAP 测速"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
            }
            .buttonStyle(GlassPressButtonStyle())
        }
    }

    // MARK: - 節拍圓點矩陣（母本 renderBeatDots + strikePulse）

    private func dotsRow(theme: TunerTheme, width: CGFloat) -> some View {
        let count = max(1, viewModel.settings.beatsPerBar)
        let slot = width / CGFloat(count)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { pillar in
                dotCell(pillar: pillar, theme: theme, slot: slot)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.cycleAccent(pillar: pillar) }
            }
        }
        .frame(height: 74)
    }

    private func dotCell(pillar: Int, theme: TunerTheme, slot: CGFloat) -> some View {
        let accents = viewModel.settings.beatAccents
        let lvl = pillar < accents.count ? accents[pillar] : 1
        let base: CGFloat = lvl == 3 ? 44 : lvl == 2 ? 40 : lvl == 1 ? 35 : 31
        let diameter = min(base, max(24, slot - 10))
        let isCurrent = viewModel.currentPillar == pillar
        let p = isCurrent ? viewModel.pulseValue : 0
        let sb: Double = lvl == 3 ? 0.14 : lvl == 2 ? 0.10 : 0.07
        // 亮起漸層走主題 token（補強段）：預備拍橙、強拍綠、
        // 其餘藍；樂池暗紅主題下三者全收斂為紅譜（見 TunerTheme）。
        let litColors: [Color] = viewModel.pulseIsCountIn && isCurrent
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
                        colors: [(viewModel.pulseIsCountIn
                                    ? theme.sharp : theme.accent)
                            .opacity(0.32 * p), Color.clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 34))
                    .frame(width: 68, height: 68)
                    .scaleEffect(0.85 + p * 0.3)
                    .allowsHitTesting(false)
                // 本體（依等級的母本樣式）。
                dotBody(lvl: lvl, theme: theme)
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
            .frame(height: 46)
            Text(L10n.t(MetronomeSettings.levelLabels[lvl]))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }

    @ViewBuilder
    private func dotBody(lvl: Int, theme: TunerTheme) -> some View {
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
                         glassOpacity: store.glassOpacity)
        default:
            Circle()
                .strokeBorder(Color(red: 128 / 255, green: 128 / 255, blue: 140 / 255,
                                    opacity: 0.5),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    // MARK: - 中央舞台：轉盤＋推子

    private func stageRow(theme: TunerTheme, dialSize: CGFloat,
                          railHeight: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Spacer(minLength: 0)
            dialView(theme: theme, size: dialSize)
            Spacer(minLength: 0)
            // 推子內縮（補強段）：頁面 .horizontal 16 ＋ 此處
            // trailing 8 = 軌道右緣距螢幕邊 24pt，離開 iOS
            // 邊緣返回手勢熱區（約 20pt）；視覺上推子僅左移
            // 8pt，刻度數字列隨之內移，其餘版面不動。
            faderView(theme: theme, height: railHeight)
                .padding(.trailing, 8)
        }
    }

    private func dialView(theme: TunerTheme, size: CGFloat) -> some View {
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
                odometer(theme: theme, dialSize: size)
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
        // 【返修批2・按鍵審計】改一般手勢：highPriority 會
        // 吞掉子層里程表的 numberDrag（點數字開編輯器／
        // 數字橫向 scrub 失效）。一般手勢下子層優先——
        // 數字區走 numberDrag、其餘錶盤走 dialDrag。
        .gesture(dialDrag)
    }

    /// BPM 里程表（母本 .bpm-num/.bpm-col：條帶兩圈 0–9、逐柱 spring）。
    private func odometer(theme: TunerTheme, dialSize: CGFloat) -> some View {
        let fontSize = min(52, max(34, dialSize * 0.30))
        let digitH = fontSize
        let digitW = fontSize * 0.62
        return HStack(spacing: 1) {
            odoColumn(index: 0, fontSize: fontSize, digitH: digitH, theme: theme)
                .frame(width: viewModel.odoHundredsBlank ? 0 : digitW)
                .opacity(viewModel.odoHundredsBlank ? 0 : 1)
            odoColumn(index: 1, fontSize: fontSize, digitH: digitH, theme: theme)
                .frame(width: digitW)
            odoColumn(index: 2, fontSize: fontSize, digitH: digitH, theme: theme)
                .frame(width: digitW)
        }
        .contentShape(Rectangle())
        .gesture(numberDrag)
    }

    private func odoColumn(index: Int, fontSize: CGFloat, digitH: CGFloat,
                           theme: TunerTheme) -> some View {
        let m = index < viewModel.odoPositions.count ? viewModel.odoPositions[index] : 0
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

    // MARK: - 推子（母本 .fader：相對拖動、吸附、橡皮筋、spring 填充）

    private func faderView(theme: TunerTheme, height: CGFloat) -> some View {
        // 【對照母本審計・Laurent 點名】母本推子是 iOS 控制
        // 中心式膠囊（.bpm-fader-rail 注解原文）：全圓膠囊
        // 軌（寬 57）、上下限籤在軌的上下同軸、亮填充自底
        // 升起＋深度內影、字形隨填充覆蓋變色。舊原生是寬 46
        // 圓角 14 的矩形軌＋籤列在左側，形狀與位置皆不符。
        let railH = max(76, height - 36)
        let fillH = max(14, railH * CGFloat(viewModel.faderRatio))
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
                // 【液態玻璃全量替換】軌道改系統真玻璃單層
                // （原 Material＋漸層 tint 的仿製疊層撤除）：
                // 母本軌 tint 近白——深色以白 0.14 染、淺色
                // 以中灰 0.16 染，折射與邊緣高光由本體給出。
                Capsule()
                    .fill(.clear)
                    .glassEffect(
                        .regular.tint(dark
                            ? Color.white.opacity(0.14)
                            : Color(red: 120 / 255, green: 120 / 255,
                                    blue: 128 / 255).opacity(0.16)),
                        in: Capsule())

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
            .overlay {
                // 母本軌邊 1px（深 白 0.26／淺 黑 0.06）：
                // 控制中心膠囊在亮背景上的輪廓線，保留。
                Capsule()
                    .strokeBorder(dark ? Color.white.opacity(0.26)
                                       : Color.black.opacity(0.06),
                                  lineWidth: 1)
            }
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

    private func bentoGrid(theme: TunerTheme) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                sigTile(theme: theme)
                menuTile(theme: theme, title: L10n.t("细分"),
                         value: L10n.t(MetronomeSettings.subdivisionOptions
                            .first { $0.value == viewModel.settings.subdivision }?.label ?? "")) {
                    ForEach(Array(MetronomeSettings.subdivisionOptions.enumerated()),
                            id: \.offset) { _, option in
                        Button {
                            viewModel.setSubdivision(option.value)
                        } label: {
                            menuItemLabel(L10n.t(option.label),
                                          checked: viewModel.settings.subdivision == option.value)
                        }
                    }
                }
                menuTile(theme: theme, title: L10n.t("音色"),
                         value: viewModel.settings.timbre.displayName) {
                    ForEach(MetronomeTimbre.allCases, id: \.self) { timbre in
                        Button {
                            viewModel.setTimbre(timbre)
                        } label: {
                            menuItemLabel(timbre.displayName,
                                          checked: viewModel.settings.timbre == timbre)
                        }
                    }
                }
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
                        tileLabel(theme: theme, title: L10n.t("重音分组"),
                                  value: viewModel.currentGrouping
                                    .map(String.init).joined(separator: "+"))
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    Spacer(minLength: 0)
                }
            }
            wideMenuRow(theme: theme, title: L10n.t("预设"),
                        value: viewModel.activePreset.map {
                            $0.builtin ? L10n.t($0.name) : $0.name
                        } ?? L10n.t("选择")) {
                Section(L10n.t("内建")) {
                    ForEach(MetronomePreset.builtins) { preset in
                        Button {
                            viewModel.applyPreset(preset)
                        } label: {
                            menuItemLabel(L10n.t(preset.name),
                                          checked: viewModel.activePresetId == preset.id)
                        }
                    }
                }
                if !viewModel.userPresets.isEmpty {
                    Section(L10n.t("自订")) {
                        ForEach(viewModel.userPresets) { preset in
                            Button {
                                viewModel.applyPreset(preset)
                            } label: {
                                menuItemLabel(preset.name,
                                              checked: viewModel.activePresetId == preset.id)
                            }
                        }
                    }
                }
                Divider()
                Button(L10n.t("保存当前为预设")) { showSavePreset = true }
                if let active = viewModel.activePreset, !active.builtin {
                    Button(L10n.t("删除当前预设"), role: .destructive) { showDeletePreset = true }
                }
            }
            wideMenuRow(theme: theme, title: L10n.t("渐速"),
                        value: viewModel.rampState.active
                            ? "\(viewModel.rampState.from) → \(viewModel.rampState.to)"
                            : L10n.t("关闭")) {
                ForEach(RampQuickScheme.all) { scheme in
                    Button {
                        if viewModel.applyRampQuick(scheme) { showCustomRamp = true }
                    } label: {
                        menuItemLabel(L10n.t(scheme.label), checked: false)
                    }
                }
            }
        }
    }

    private func sigTile(theme: TunerTheme) -> some View {
        let s = viewModel.settings
        let value = "\(s.beatsPerBar)/\(s.beatUnit)" + (s.isDottedBeat ? " ♩." : "")
        return ZStack(alignment: .topTrailing) {
            Menu {
                ForEach(Array(MetronomeSettings.signatures.enumerated()),
                        id: \.offset) { _, sig in
                    Button {
                        viewModel.setSignature(beats: sig.beats, unit: sig.unit)
                    } label: {
                        menuItemLabel("\(sig.beats)/\(sig.unit)",
                                      checked: s.beatsPerBar == sig.beats
                                        && s.beatUnit == sig.unit)
                    }
                }
                Divider()
                Button {
                    viewModel.setDottedBeat(!s.dottedBeat)
                } label: {
                    menuItemLabel(L10n.t("附点计拍 (♩.)"),
                                  checked: s.dottedBeat)
                }
            } label: {
                tileLabel(theme: theme, title: L10n.t("拍号"), value: value)
            }
            Button {
                viewModel.resetAccents()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel(L10n.t("重置重音"))
        }
    }

    private func menuTile<Content: View>(theme: TunerTheme, title: String,
                                         value: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            tileLabel(theme: theme, title: title, value: value)
        }
    }

    private func wideMenuRow<Content: View>(theme: TunerTheme, title: String,
                                            value: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
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
            .frame(height: 42)
            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func tileLabel(theme: TunerTheme, title: String, value: String) -> some View {
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
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func menuItemLabel(_ text: String, checked: Bool) -> some View {
        if checked {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }

    // MARK: - START 主鈕（母本 btnToggleMetro：運行中 brightness 呼吸）

    private func startButton(theme: TunerTheme) -> some View {
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
            .frame(height: 52)
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

    // MARK: - 手勢（轉盤豎拖／數字點按・橫 scrub・豎拖／推子相對拖）

    @State private var dialStartBpm: Int?
    @State private var dialStartY: CGFloat = 0

    private var dialDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // 【返修批2】自癒再武裝：上一拖被系統取消、
                // 看門狗已 endAdjust 時，start 值可能殘留；
                // VM 不在 adjusting 即視為新拖、重新取樣。
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
                if wasTap { openEditor() }
            }
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
                // 超界量給橡皮筋（母本：rail 依超界縮放、值本身鉗制）。
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

/// 長按連調的時序協調（@MainActor 類別，避免在 View 結構內以
/// @Sendable 閉包捕獲狀態）：按下 340 ms 後首發、其後每 62 ms
/// 一次；340 ms 內抬手 → 由 pressEnded 補發一次普通點按
/// （母本 addHoldRepeat 的 click 吞吐語義）。
@MainActor
private final class HoldRepeater: ObservableObject {
    private var task: Task<Void, Never>?
    private var fired = false
    /// 按壓中（供按壓亮斑回饋，母本 .glass-press）。
    @Published private(set) var isPressing = false

    func pressBegan(action: @escaping () -> Void) {
        guard task == nil else { return }
        isPressing = true
        fired = false
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 340_000_000)
                self?.fired = true
                action()
                // 【返修批2・按鍵審計】連調上限 500 發
                // （≈31 s）：pressing(false) 若因手勢取消
                // 未送達，連調不致無限持續。
                for _ in 0..<500 {
                    try await Task.sleep(nanoseconds: 62_000_000)
                    action()
                }
            } catch {
                // 已取消（手指抬起）：結束連調。
            }
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

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("渐速参数")) {
                    LabeledContent(L10n.t("起始 BPM")) {
                        TextField("20–300", text: $fromText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(L10n.t("目标 BPM")) {
                        TextField("20–300", text: $toText)
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
                Section {
                    Button(L10n.t("开始渐速")) {
                        let from = Int(fromText) ?? -1
                        let to = Int(toText) ?? -1
                        let bars = Int(barsText) ?? -1
                        let step = Int(stepText) ?? -1
                        if viewModel.startCustomRamp(from: from, to: to,
                                                     bars: bars, step: step) {
                            isPresented = false
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
                            .font(.footnote)
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
