import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(L10n.languageKey) private var language = L10n.system
    @State private var showBackups = false
    @State private var askSave = false
    @State private var askReload = false
    @State private var askFolderName = false
    @State private var folderName = ""
    @State private var conflict: SaveOutcome?
    @State private var showError = false

    var body: some View {
        @Bindable var store = store
        content
            .navigationTitle(L("app.title"))
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .searchable(text: $store.search, placement: .toolbar, prompt: L("tb.search"))
            .inspector(isPresented: Binding(get: { store.openFolder != nil }, set: { if !$0 { store.openFolder = nil } })) {
                FolderInspector()
                    .inspectorColumnWidth(min: 300, ideal: 330, max: 460)
            }
            .sheet(isPresented: $showBackups) { BackupsSheet() }
            .alert(L("dlg.save.title"), isPresented: $askSave) {
                Button(L("dlg.cancel"), role: .cancel) {}
                Button(L("dlg.save.confirm")) { Task { await save(force: false) } }
                    .keyboardShortcut(.defaultAction)
            } message: { Text(L("dlg.save.body")) }
            .alert(L("dlg.reload.title"), isPresented: $askReload) {
                Button(L("dlg.cancel"), role: .cancel) {}
                Button(L("dlg.reload.confirm"), role: .destructive) { reload() }
            } message: { Text(L("dlg.discard")) }
            .alert(conflictTitle, isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })) {
                Button(L("dlg.cancel"), role: .cancel) {}
                if conflict == .changed {
                    Button(L("dlg.saveAnyway"), role: .destructive) { Task { await save(force: true) } }
                }
                Button(L("dlg.reload.confirm")) { reload() }.keyboardShortcut(.defaultAction)
            } message: { Text(conflict == .stale ? L("dlg.stale.body") : L("dlg.changed.body")) }
            .alert(L("dlg.newFolder.title"), isPresented: $askFolderName) {
                TextField(L("folder.name"), text: $folderName)
                Button(L("dlg.cancel"), role: .cancel) {}
                Button(L("dlg.ok")) { store.newFolderFromSelection(name: folderName) }.keyboardShortcut(.defaultAction)
            }
            .alert(L("err.title"), isPresented: $showError) {
                Button(L("dlg.ok"), role: .cancel) {}
            } message: { Text(store.errorText) }
            .onChange(of: askFolderName) { _, open in if open { folderName = L("dlg.newFolder.default") } }
            .onChange(of: store.dirty) { _, dirty in NSApp.windows.forEach { $0.isDocumentEdited = dirty } }
            .onReceive(NotificationCenter.default.publisher(for: .appSave)) { _ in requestSave() }
            .onReceive(NotificationCenter.default.publisher(for: .appReload)) { _ in requestReload() }
            .onReceive(NotificationCenter.default.publisher(for: .appBackups)) { _ in showBackups = true }
            .onExitCommand { escape() }
            .task { if store.phase == .connecting && store.info == nil { await store.connect() } }
            .id(language) // re-render every string when the language changes
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .ready:
            HomeScreenView()
                .overlay(alignment: .bottom) {
                    VStack(spacing: 12) {
                        if !store.selected.isEmpty {
                            SelectionBar(askFolderName: $askFolderName)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        DockView()
                    }
                    .padding(.bottom, 16)
                    .animation(.snappy, value: store.selected.isEmpty)
                }
                .overlay(alignment: .top) {
                    if let toast = store.toast {
                        Text(toast)
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.snappy, value: store.toast)
                .overlay {
                    if store.busy {
                        ProgressView().controlSize(.large).padding(24).glassEffect(.regular, in: .rect(cornerRadius: 18))
                    }
                }
        case .connecting:
            ProgressView(L("dev.connecting")).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label(L("empty.title"), systemImage: "iphone.slash")
            } description: {
                Text(L("empty.body") + "\n\n" + store.errorText)
            } actions: {
                Button(L("empty.retry")) { reload() }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Text(statusText)
                .font(.callout)
                .foregroundStyle(store.problems.isEmpty ? (store.dirty ? Brand.blue : .secondary) : .red)
                .help(store.problems.joined(separator: "\n"))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker(L("tb.language"), selection: $language) {
                    Text(L("lang.system")).tag(L10n.system)
                    Divider()
                    ForEach(L10n.available.sorted { L10n.nativeName($0) < L10n.nativeName($1) }, id: \.self) { code in
                        Text(L10n.nativeName(code)).tag(code)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(L10n.language.uppercased(), systemImage: "globe")
                    .labelStyle(.titleAndIcon)
            }
            .help(L("tb.language"))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { store.undo() } label: { Label(L("tb.undo"), systemImage: "arrow.uturn.backward") }
                .disabled(!store.canUndo)
                .help(L("tb.undo") + " (⌘Z)")
            Button { requestReload() } label: { Label(L("tb.reload"), systemImage: "arrow.clockwise") }
                .disabled(store.busy)
                .help(L("tb.reload") + " (⌘R)")
            Button { showBackups = true } label: { Label(L("tb.backups"), systemImage: "clock.arrow.circlepath") }
                .help(L("tb.backups"))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { requestSave() } label: { Label(L("tb.save"), systemImage: "square.and.arrow.down.on.square") }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .disabled(!store.dirty || !store.problems.isEmpty || store.busy)
                .help(store.problems.isEmpty ? L("tb.save") + " (⌘S)" : store.problems.joined(separator: "\n"))
        }
    }

    private var subtitle: String {
        guard let i = store.info, store.phase == .ready else { return store.phase == .connecting ? L("dev.connecting") : "" }
        let m = store.metrics
        // demo mode shows a made-up layout and hides the device name
        let name = Demo.isOn ? "iPhone" : i.name
        var s = L("dev.subtitle", name, i.ios, store.count, m.columns, m.rows, m.folderColumns, m.folderRows)
        if store.matches != nil {
            let n = store.resultCount
            s += " · " + (n == 0 ? L("st.noResults") : n == 1 ? L("st.result") : L("st.results", n))
        }
        return s
    }

    private var statusText: String {
        if let p = store.problems.first { return p }
        if store.dirty { return L("st.unsaved") }
        return store.phase == .ready ? L("st.synced") : ""
    }

    private var conflictTitle: String { conflict == .stale ? L("dlg.stale.title") : L("dlg.changed.title") }

    private func requestSave() {
        guard store.dirty, store.problems.isEmpty, !store.busy else { return }
        askSave = true
    }

    private func requestReload() {
        if store.dirty { askReload = true } else { reload() }
    }

    private func reload() {
        IconCache.shared.reset()
        Task { await store.connect() }
    }

    private func save(force: Bool) async {
        switch await store.save(force: force) {
        case .stale: conflict = .stale
        case .changed: conflict = .changed
        case .failed: showError = true
        case .ok: break
        }
    }

    private func escape() {
        if store.openFolder != nil { store.openFolder = nil }
        else if !store.selected.isEmpty { store.selected.removeAll() }
        else if !store.search.isEmpty { store.search = "" }
    }
}

extension Notification.Name {
    static let appSave = Notification.Name("appSave")
    static let appReload = Notification.Name("appReload")
    static let appBackups = Notification.Name("appBackups")
}
