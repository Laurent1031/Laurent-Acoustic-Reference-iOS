import SwiftUI

/// 樂器庫（母本 instModal，行 5509）：標題列＋分類分段＋搜尋＋
/// 兩欄卡片格＋（自訂分頁才有的）新增自訂樂器。行為對照母本
/// renderInstrumentGrid（行 8401）：
/// - 搜尋非空時跨分類以 名稱／英文／調號 子字串比對；
/// - 分頁過濾：cat 相符，或自訂分頁恆含全部自訂樂器；
/// - 卡片：中文名＋收藏星（右上）、英文名＋藍色調號（下行），
///   選中卡藍框藍底；自訂卡另有編輯／刪除鈕；
/// - 點卡選樂器並關閉（母本 90 ms 後關 sheet）；點星切換收藏，
///   加入時星標蹦出特效（母本 burstStar，行 6808）；
/// - 刪除為兩步行內確認（母本 .ci-del-btn.confirming，2.6 s 視窗）；
/// - 新增／編輯表單接管整個 sheet 主體（母本 showCustomInstForm）。
struct InstrumentLibraryView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var tab: InstrumentCategory
    @State private var searchQuery = ""
    @State private var showingForm = false
    @State private var editing: Instrument?
    @State private var minimumFavoriteWarning = false

    init(store: AppStore) {
        self.store = store
        // 開啟時落在目前樂器所在分頁（母本開啟後捲動至 active 卡，
        // 其前提即 active 卡在清單內；instCat 殘留他頁時母本無
        // active 卡可捲——原生版以「落在目前樂器分頁」等價呈現）。
        let current = store.selectedInstrument
        _tab = State(initialValue: current.isCustom ? .custom : current.category)
    }

    private var visibleInstruments: [Instrument] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            return store.allInstruments.filter {
                "\($0.name) \($0.englishName) \($0.keyName)".lowercased().contains(query)
            }
        }
        return store.allInstruments.filter {
            $0.category == tab || (tab == .custom && $0.isCustom)
        }
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                if showingForm {
                    CustomInstrumentFormView(
                        store: store,
                        editing: editing,
                        onCancel: { showingForm = false },
                        onSaved: { saved in
                            store.selectInstrument(id: saved.id)
                            tab = .custom
                            showingForm = false
                        }
                    )
                } else {
                    VStack(spacing: 10) {
                        categorySegment(theme: theme)
                        searchField(theme: theme)
                        grid(theme: theme)
                        if tab == .custom && searchQuery.isEmpty {
                            addCustomButton(theme: theme)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle(L10n.t("乐器库与常用收藏"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 【返修批2】左上「點亮 ★…」提示經 Laurent
                // 指示去掉（工具列裡被擠成圓形殘片、字截斷）。
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成")) { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    // MARK: - 分類分段（母本 instCatSeg；橫滑膠囊）

    private func categorySegment(theme: TunerTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(InstrumentCatalog.categories) { entry in
                    Button {
                        tab = entry.category
                        // 母本：搜尋中點分類 = 瀏覽該分類，清查詢。
                        if !searchQuery.isEmpty { searchQuery = "" }
                    } label: {
                        Text(L10n.localizedName(entry.name))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(tab == entry.category ? theme.textPrimary : theme.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                GlassChipBackground(selected: tab == entry.category,
                                                    theme: theme,
                                                    glassOpacity: store.glassOpacity,
                                                    bareUnselected: true)
                            }
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            .padding(3)
        }
        .glassBackground(in: Capsule(), theme: theme, glassOpacity: store.glassOpacity)
    }

    // MARK: - 搜尋（母本 instSearchInput）

    private func searchField(theme: TunerTheme) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            TextField(L10n.t("搜索乐器（名称 / 英文 / 调号）"), text: $searchQuery)
                .font(.system(size: 14))
                .foregroundStyle(theme.textPrimary)
                .autocorrectionDisabled()
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
    }

    // MARK: - 卡片格

    private func grid(theme: TunerTheme) -> some View {
        ScrollView {
            if visibleInstruments.isEmpty {
                Text(searchQuery.isEmpty
                     ? L10n.t("尚无自订乐器，点下方「＋ 新增自订乐器」建立")
                     : L10n.t("未找到匹配的乐器，换个关键词试试"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10),
                              GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(visibleInstruments) { inst in
                        InstrumentCard(
                            store: store,
                            instrument: inst,
                            isActive: inst.id == store.selectedInstrumentId,
                            theme: theme,
                            onSelect: {
                                store.selectInstrument(id: inst.id)
                                HapticsEngine.shared.tap(milliseconds: 8)
                                // 母本卡片選樂器：uiSound("switch")（行 8468）。
                                UISoundEngine.shared.play(.switch)
                                dismiss()
                            },
                            onEdit: {
                                editing = inst
                                showingForm = true
                            },
                            onMinimumFavorite: {
                                minimumFavoriteWarning = true
                            }
                        )
                    }
                }
            }
        }
        .alert(L10n.t("请至少保留 1 个常用乐器"), isPresented: $minimumFavoriteWarning) {
            Button(L10n.t("好"), role: .cancel) {}
        }
    }

    private func addCustomButton(theme: TunerTheme) -> some View {
        Button {
            editing = nil
            showingForm = true
        } label: {
            Text(L10n.t("＋ 新增自订乐器"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

/// 樂器卡片（母本 .inst-card）：點按選樂器；星標切換收藏（加入時
/// 蹦出特效）；自訂樂器附編輯／兩步刪除。
private struct InstrumentCard: View {
    @ObservedObject var store: AppStore
    let instrument: Instrument
    let isActive: Bool
    let theme: TunerTheme
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onMinimumFavorite: () -> Void

    @State private var starScale: CGFloat = 1
    @State private var burstProgress: CGFloat = 1
    @State private var confirmingDelete = false

    private var isFavorite: Bool { store.isFavorite(instrument.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text(L10n.localizedName(instrument.name))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if instrument.isCustom {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    Button { tapDelete() } label: {
                        Text(confirmingDelete ? L10n.t("确认删除？") : "✕")
                            .font(.system(size: confirmingDelete ? 10.5 : 11,
                                        weight: .semibold))
                            .foregroundStyle(confirmingDelete ? theme.clipWarning : theme.textSecondary)
                            .frame(height: 24)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
                starButton
            }
            HStack {
                Text(instrument.englishName)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                Spacer()
                // 母本卡片調號用數據原值 keyName（古箏恆 "1 = D"；
                // 頂行標籤才隨目前調號，見 AppStore.keyLabel）。
                Text(instrument.keyName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            // 【液態玻璃全量替換】卡面改真玻璃；選中態以
            // accent 淡色墊在玻璃之後襯色（不覆蓋玻璃面）。
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.accent.opacity(theme.isDark ? 0.16 : 0.10))
                }
                GlassSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                             theme: theme, glassOpacity: store.glassOpacity)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isActive ? theme.accent.opacity(0.65) : Color.clear,
                              lineWidth: 1.2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onSelect() }
    }

    // MARK: - 收藏星＋蹦出特效（母本 burstStar，行 6808）

    private var starButton: some View {
        Button { toggleFavorite() } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFavorite ? theme.favoriteStar : theme.textMuted)
                .scaleEffect(starScale)
                .frame(width: 26, height: 26)
                .overlay { burstDots }
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    /// 六顆火花：角度 2πi/6＋0.4、距離 20＋(i%2)×6 px、480 ms、
    /// delay 100 ms、cubic-bezier(0.22,1,0.36,1)、scale 1→0.4、
    /// opacity →0（母本 .burst-dot 與 @keyframes burstFly）。
    @ViewBuilder
    private var burstDots: some View {
        if burstProgress < 1 {
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let angle = 2 * Double.pi * Double(i) / 6 + 0.4
                    let distance = (20 + Double(i % 2) * 6) * burstProgress
                    Circle()
                        .fill(theme.warn)
                        .frame(width: 4, height: 4)
                        .scaleEffect(1 - 0.6 * burstProgress)
                        .opacity(1 - burstProgress)
                        .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                }
            }
        }
    }

    private func toggleFavorite() {
        // 母本行 6799：收藏切換 uiSound——加入 "switch"、移除
        // "tick"；低於下限被拒時母本提前 return、僅 toast、
        // 無音效無震動，原生比照其他拒絕點補 "warn"（有意
        // 差異，見補強段報告）。
        switch store.toggleFavorite(id: instrument.id) {
        case .added:
            HapticsEngine.shared.tap(milliseconds: 8)
            UISoundEngine.shared.play(.switch)
            playBurst()
        case .removed:
            UISoundEngine.shared.play(.tick)
        case .rejectedMinimum:
            UISoundEngine.shared.play(.warn)
            onMinimumFavorite()
        }
    }

    /// 星：300 ms 彈至 1.28（峰值在 0.35 處、母本
    /// cubic-bezier(0.34,1.56,0.64,1) 的過衝曲線）；火花隨後飛出。
    private func playBurst() {
        withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.105)) {
            starScale = 1.28
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 105_000_000)
            withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.195)) {
                starScale = 1
            }
        }
        burstProgress = 0
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.48).delay(0.1)) {
            burstProgress = 1
        }
    }

    // MARK: - 兩步刪除（母本行 8448：確認態 2.6 s）

    private func tapDelete() {
        if confirmingDelete {
            confirmingDelete = false
            // 母本行 7465：確認刪除 uiSound("warn")。
            UISoundEngine.shared.play(.warn)
            store.deleteCustomInstrument(id: instrument.id)
        } else {
            confirmingDelete = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                confirmingDelete = false
            }
        }
    }
}

/// 自訂樂器表單（母本 customInstForm，行 5536）：欄位、選項、
/// 預設與驗證逐項對照母本保存處理（行 7836）。
private struct CustomInstrumentFormView: View {
    @ObservedObject var store: AppStore
    let editing: Instrument?
    let onCancel: () -> Void
    let onSaved: (Instrument) -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String
    @State private var englishName: String
    @State private var keyName: String
    @State private var transposition: Int
    @State private var category: InstrumentCategory
    @State private var lowMidi: Int
    @State private var highMidi: Int
    @State private var nameError = false
    @State private var rangeError = false

    /// 母本 ciTrans 十個選項（行 5545；zh-TW 渲染值，預設 -9）。
    private struct TranspositionOption: Identifiable {
        var value: Int
        var label: String
        var id: Int { value }
    }

    /// 選項標籤為 zh-CN 源串（母本 ciTrans 原文）；顯示時經
    /// L10n.t 查字典（十條皆為字典鍵）。
    private static let transpositionOptions: [TranspositionOption] = [
        TranspositionOption(value: 0, label: "同度 · 记谱 = 实音（钢琴/长笛）"),
        TranspositionOption(value: -2, label: "降B乐器 · 记谱高大二度（单簧管/小号）"),
        TranspositionOption(value: -3, label: "A调 · 记谱高小三度（A调单簧管）"),
        TranspositionOption(value: -7, label: "F调 · 记谱高纯五度（圆号/英国管）"),
        TranspositionOption(value: -9, label: "降E · 记谱高大六度（中音萨克斯）"),
        TranspositionOption(value: -12, label: "低八度 · 记谱高八度（低音提琴）"),
        TranspositionOption(value: -21, label: "降E低音 · 记谱高十三度（上低音萨克斯）"),
        TranspositionOption(value: 12, label: "高八度 · 记谱低八度（短笛）"),
        TranspositionOption(value: 2, label: "D调 · 记谱低大二度"),
        TranspositionOption(value: 5, label: "F调 · 记谱低纯四度"),
    ]

    init(store: AppStore, editing: Instrument?,
         onCancel: @escaping () -> Void,
         onSaved: @escaping (Instrument) -> Void) {
        self.store = store
        self.editing = editing
        self.onCancel = onCancel
        self.onSaved = onSaved
        if let editing {
            // 母本 startEditCustomInstrument（行 7762）：en 為
            // "Custom" 時清空；音域以 pad 反推回 MIDI。
            _name = State(initialValue: editing.name)
            _englishName = State(initialValue: editing.englishName == "Custom" ? "" : editing.englishName)
            _keyName = State(initialValue: editing.keyName)
            _transposition = State(initialValue: editing.transposition)
            _category = State(initialValue: editing.category)
            _lowMidi = State(initialValue: Self.midiOf(freq: editing.minFrequency, pad: 0.85))
            _highMidi = State(initialValue: Self.midiOf(freq: editing.maxFrequency, pad: 1.15))
        } else {
            _name = State(initialValue: "")
            _englishName = State(initialValue: "")
            _keyName = State(initialValue: "")
            _transposition = State(initialValue: -9)
            _category = State(initialValue: .custom)
            _lowMidi = State(initialValue: 48)
            _highMidi = State(initialValue: 84)
        }
    }

    /// 母本 midiOf（行 7777）：round(69 + 12·log2((f/pad)/440))。
    private static func midiOf(freq: Double, pad: Double) -> Int {
        Int((69 + 12 * log2((freq / pad) / 440)).rounded())
    }

    var body: some View {
        let theme = store.resolvedTheme(system: colorScheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                field(theme: theme) {
                    TextField(L10n.t("乐器名称（如：降E调高音萨克斯）"), text: $name)
                        .onChange(of: name) { _, _ in nameError = false }
                }
                if nameError {
                    Text(L10n.t("请填写乐器名称"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.clipWarning)
                }

                HStack(spacing: 8) {
                    field(theme: theme) {
                        TextField(L10n.t("英文/副标（可选）"), text: $englishName)
                    }
                    field(theme: theme) {
                        TextField(L10n.t("调号（如 1 = E♭，可选）"), text: $keyName)
                    }
                }

                labeledPicker(theme: theme, label: L10n.t("移调关系（记谱与实音）")) {
                    Picker(L10n.t("移调关系（记谱与实音）"), selection: $transposition) {
                        ForEach(Self.transpositionOptions) { option in
                            Text(L10n.t(option.label)).tag(option.value)
                        }
                    }
                }

                labeledPicker(theme: theme, label: L10n.t("归属分类（自订栏始终可见）")) {
                    Picker(L10n.t("归属分类（自订栏始终可见）"), selection: $category) {
                        Text(L10n.t("仅自订栏")).tag(InstrumentCategory.custom)
                        ForEach(InstrumentCatalog.categories.filter { $0.category != .custom }) { entry in
                            Text(L10n.localizedName(entry.name)).tag(entry.category)
                        }
                    }
                }

                HStack(spacing: 8) {
                    labeledPicker(theme: theme, label: L10n.t("最低音（实音）")) {
                        Picker(L10n.t("最低音（实音）"), selection: $lowMidi) {
                            ForEach(24...96, id: \.self) { midi in
                                Text(PitchMath.noteName(midi: midi)).tag(midi)
                            }
                        }
                    }
                    labeledPicker(theme: theme, label: L10n.t("最高音（实音）")) {
                        Picker(L10n.t("最高音（实音）"), selection: $highMidi) {
                            ForEach(24...96, id: \.self) { midi in
                                Text(PitchMath.noteName(midi: midi)).tag(midi)
                            }
                        }
                    }
                }
                .onChange(of: lowMidi) { _, _ in rangeError = false }
                .onChange(of: highMidi) { _, _ in rangeError = false }
                if rangeError {
                    Text(L10n.t("最高音必须高于最低音"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.clipWarning)
                }

                HStack(spacing: 8) {
                    Button { onCancel() } label: {
                        Text(L10n.t("取消"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    Button { save() } label: {
                        Text(editing == nil ? L10n.t("保存自订乐器") : L10n.t("保存修改"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(theme.accent,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func field<Content: View>(theme: TunerTheme,
                                      @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 15))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
    }

    private func labeledPicker<Content: View>(
        theme: TunerTheme, label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.textMuted)
            content()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 42)
                .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous), theme: theme, glassOpacity: store.glassOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            nameError = true
            return
        }
        guard highMidi > lowMidi else {
            rangeError = true
            return
        }
        let saved = store.saveCustomInstrument(
            editingId: editing?.id, name: trimmedName,
            englishName: englishName, keyName: keyName,
            transposition: transposition, category: category,
            lowMidi: lowMidi, highMidi: highMidi)
        HapticsEngine.shared.tap(milliseconds: 12)
        // 母本行 7686：自訂樂器保存 uiSound("success")。
        UISoundEngine.shared.play(.success)
        onSaved(saved)
    }
}
