import Foundation
import Observation

/// Where an icon lives: Dock, a Home Screen page or a page of a folder.
enum Zone: Hashable, Sendable {
    case dock
    case page(Int)
    case folder(String, Int)
}

struct Location: Hashable {
    var zone: Zone
    var index: Int
}

/// Dock, pages and folders as lists of ids, exactly as on the iPhone.
struct HomeModel: Equatable, Sendable {
    var dock: [String] = []
    var pages: [[String]] = []
    var folders: [String: Folder] = [:]
}

enum SaveOutcome { case ok, stale, changed, failed }

@MainActor
@Observable
final class AppStore {
    enum Phase { case connecting, ready, failed }

    var phase: Phase = .connecting
    var errorText = ""
    var info: DeviceInfo?
    var metrics = Metrics.iPhone
    var count = 0
    var items: [String: Item] = [:]
    var model = HomeModel()
    private(set) var base = HomeModel()
    private(set) var undoStack: [HomeModel] = []
    var selected: Set<String> = []
    var openFolder: String?
    var search = ""
    var busy = false
    var toast: String?

    // drag and drop state
    var dragging: String?
    var hoverFolder: String?
    var insertHint: (id: String, after: Bool)?

    private var sig = ""
    private var newFolderN = 0
    private var toastTask: Task<Void, Never>?

    // MARK: derived

    var dirty: Bool { phase == .ready && model != base }
    var canUndo: Bool { !undoStack.isEmpty }
    var folderCap: Int { metrics.folderColumns * metrics.folderRows }
    var pageCap: Int { metrics.columns * metrics.rows }

    func isFolder(_ id: String) -> Bool { model.folders[id] != nil }
    func nameOf(_ id: String) -> String { model.folders[id]?.name ?? items[id]?.name ?? "" }
    func canGoInFolder(_ id: String) -> Bool { !isFolder(id) && items[id].map { !$0.isWidget } ?? false }
    func folderCount(_ fid: String) -> Int { model.folders[fid]?.pages.reduce(0) { $0 + $1.count } ?? 0 }

    /// Grid cells taken by an icon: widgets span several cells, as on the iPhone.
    func span(_ id: String) -> (cols: Int, rows: Int) {
        guard let it = items[id], it.isWidget else { return (1, 1) }
        switch it.size ?? "small" {
        case "medium": return (metrics.columns, 2)
        case "large": return (metrics.columns, 4)
        case "extraLarge": return (metrics.columns, 4)
        default: return (2, 2)
        }
    }

    func slots(_ id: String) -> Int { let s = span(id); return s.cols * s.rows }
    func pageSlots(_ page: [String]) -> Int { page.reduce(0) { $0 + slots($1) } }

    var problems: [String] {
        var out: [String] = []
        if model.dock.count > metrics.dockMax { out.append(L("err.dock_full", model.dock.count, metrics.dockMax)) }
        for (i, p) in model.pages.enumerated() {
            let used = pageSlots(p)
            if used > pageCap { out.append(L("err.page_full", i + 1, used, pageCap)) }
        }
        let pages = model.pages.filter { !$0.isEmpty }.count
        if pages > metrics.maxPages { out.append(L("err.too_many_pages", pages, metrics.maxPages)) }
        for (fid, f) in model.folders where locate(fid) != nil {
            for (k, p) in f.pages.enumerated() where p.count > folderCap {
                out.append(L("err.folder_page_full", f.name, k + 1, p.count, folderCap))
            }
            let fp = f.pages.filter { !$0.isEmpty }.count
            if fp > metrics.folderMaxPages { out.append(L("err.folder_too_many_pages", f.name, fp, metrics.folderMaxPages)) }
        }
        return out
    }

    /// Ids matching the search (apps, plus folders containing a match); nil when not searching.
    var matches: Set<String>? {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        var hit = Set(items.values.filter { $0.name.lowercased().contains(q) || ($0.key ?? "").lowercased().contains(q) }.map(\.id))
        for (fid, f) in model.folders where f.name.lowercased().contains(q) || f.pages.joined().contains(where: hit.contains) {
            hit.insert(fid)
        }
        return hit
    }

    var resultCount: Int { matches.map { $0.filter { items[$0] != nil }.count } ?? 0 }

    // MARK: locating and lists

    func locate(_ id: String) -> Location? {
        if let i = model.dock.firstIndex(of: id) { return Location(zone: .dock, index: i) }
        for (p, page) in model.pages.enumerated() {
            if let i = page.firstIndex(of: id) { return Location(zone: .page(p), index: i) }
        }
        for (fid, f) in model.folders {
            for (k, page) in f.pages.enumerated() {
                if let i = page.firstIndex(of: id) { return Location(zone: .folder(fid, k), index: i) }
            }
        }
        return nil
    }

    func list(_ zone: Zone) -> [String] {
        switch zone {
        case .dock: return model.dock
        case .page(let p): return p < model.pages.count ? model.pages[p] : []
        case .folder(let f, let k):
            guard let folder = model.folders[f], k < folder.pages.count else { return [] }
            return folder.pages[k]
        }
    }

    /// Edits the list behind a zone; the page right after the last one is created.
    private func edit(_ zone: Zone, _ body: (inout [String]) -> Void) {
        switch zone {
        case .dock:
            body(&model.dock)
        case .page(let p):
            while model.pages.count <= p { model.pages.append([]) }
            body(&model.pages[p])
        case .folder(let f, let k):
            guard model.folders[f] != nil else { return }
            while model.folders[f]!.pages.count <= k { model.folders[f]!.pages.append([]) }
            body(&model.folders[f]!.pages[k])
        }
    }

    private func remove(_ ids: Set<String>) {
        model.dock.removeAll(where: ids.contains)
        for p in model.pages.indices { model.pages[p].removeAll(where: ids.contains) }
        for fid in model.folders.keys {
            for k in model.folders[fid]!.pages.indices { model.folders[fid]!.pages[k].removeAll(where: ids.contains) }
        }
    }

    private func cleanFolders() {
        for fid in model.folders.keys {
            let pages = model.folders[fid]!.pages.enumerated().filter { !$0.element.isEmpty || $0.offset == 0 }.map(\.element)
            model.folders[fid]!.pages = pages
        }
    }

    /// As on the iPhone: a full page pushes its last icons to the next page.
    private func reflowHome(from start: Int) {
        var i = max(0, start)
        while i < model.pages.count {
            while model.pages[i].count > 1 && pageSlots(model.pages[i]) > pageCap {
                let last = model.pages[i].removeLast()
                if i + 1 >= model.pages.count { model.pages.append([]) }
                model.pages[i + 1].insert(last, at: 0)
            }
            i += 1
        }
    }

    private func reflowFolder(_ fid: String, from start: Int) {
        guard model.folders[fid] != nil else { return }
        var k = max(0, start)
        while k < model.folders[fid]!.pages.count {
            while model.folders[fid]!.pages[k].count > folderCap {
                let last = model.folders[fid]!.pages[k].removeLast()
                if k + 1 >= model.folders[fid]!.pages.count { model.folders[fid]!.pages.append([]) }
                model.folders[fid]!.pages[k + 1].insert(last, at: 0)
            }
            k += 1
        }
    }

    private func reflow(_ zone: Zone?) {
        switch zone {
        case .page(let p): reflowHome(from: p)
        case .folder(let f, let k): reflowFolder(f, from: k)
        default: break
        }
    }

    private func addToFolder(_ fid: String, _ ids: [String]) {
        guard model.folders[fid] != nil else { return }
        if model.folders[fid]!.pages.isEmpty { model.folders[fid]!.pages = [[]] }
        for id in ids {
            if model.folders[fid]!.pages[model.folders[fid]!.pages.count - 1].count >= folderCap {
                model.folders[fid]!.pages.append([])
            }
            model.folders[fid]!.pages[model.folders[fid]!.pages.count - 1].append(id)
        }
    }

    /// Puts an id where another one was; next to its folder if that was inside a folder.
    private func insert(_ id: String, at loc: Location?) {
        guard let loc else {
            if model.pages.isEmpty { model.pages.append([]) }
            model.pages[model.pages.count - 1].append(id)
            return
        }
        if case .folder(let f, _) = loc.zone {
            insert(id, at: locate(f).map { Location(zone: $0.zone, index: $0.index + 1) })
            return
        }
        edit(loc.zone) { $0.insert(id, at: min(loc.index, $0.count)) }
    }

    // MARK: edits (each one is a single undo step)

    func mutate(_ body: () -> Void) {
        let before = model
        body()
        if model != before {
            undoStack.append(before)
            if undoStack.count > 200 { undoStack.removeFirst() }
        }
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        model = prev
        if let f = openFolder, model.folders[f] == nil { openFolder = nil }
    }

    /// Can `id` be dropped into `zone`?
    func accepts(_ id: String?, into zone: Zone) -> Bool {
        guard let id, items[id] != nil || isFolder(id) else { return false }
        switch zone {
        case .dock:
            if items[id]?.isWidget == true { return false }
            if case .dock = locate(id)?.zone { return true }
            return model.dock.count < metrics.dockMax
        case .folder:
            return canGoInFolder(id)
        case .page:
            return true
        }
    }

    /// Moves `id` so that it ends up at `index` of `zone` (index counted before the move).
    func move(_ id: String, to zone: Zone, at index: Int) {
        guard accepts(id, into: zone), let from = locate(id) else { return }
        mutate {
            var idx = index
            if from.zone == zone && from.index < idx { idx -= 1 }
            remove([id])
            edit(zone) { $0.insert(id, at: min(max(idx, 0), $0.count)) }
            reflow(zone)
            cleanFolders()
        }
    }

    func drop(_ id: String, intoFolder fid: String) {
        guard fid != id, canGoInFolder(id), model.folders[fid] != nil else { return }
        mutate {
            remove([id])
            addToFolder(fid, [id])
            cleanFolders()
        }
        show(L("toast.addedTo", nameOf(id), nameOf(fid)))
    }

    func movePage(_ from: Int, by delta: Int) {
        let to = from + delta
        guard model.pages.indices.contains(from), model.pages.indices.contains(to) else { return }
        mutate { model.pages.swapAt(from, to) }
    }

    func addPage() { mutate { model.pages.append([]) } }

    func deletePage(_ i: Int) {
        guard model.pages.indices.contains(i), model.pages[i].isEmpty else { return }
        mutate { _ = model.pages.remove(at: i) }
    }

    func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    enum Target: Hashable { case dock, page(Int), newPage, folder(String) }

    func moveSelected(to target: Target) {
        var ids = selected.filter { items[$0] != nil || isFolder($0) }.sorted { (locate($0).map(order) ?? 0) < (locate($1).map(order) ?? 0) }
        var skipped: [String] = []
        switch target {
        case .folder:
            skipped = ids.filter { !canGoInFolder($0) }.map(nameOf)
            ids = ids.filter(canGoInFolder)
        case .dock:
            skipped = ids.filter { items[$0]?.isWidget == true }.map(nameOf)
            ids = ids.filter { items[$0]?.isWidget != true }
        default: break
        }
        guard !ids.isEmpty else { show(L("toast.skipped", skipped.joined(separator: ", "))); return }
        mutate {
            remove(Set(ids))
            switch target {
            case .dock: model.dock.append(contentsOf: ids)
            case .newPage:
                model.pages.append(ids)
                reflowHome(from: model.pages.count - 1)
            case .page(let p):
                edit(.page(p)) { $0.append(contentsOf: ids) }
                reflowHome(from: p)
            case .folder(let f): addToFolder(f, ids)
            }
            cleanFolders()
        }
        selected.removeAll()
        show(skipped.isEmpty ? L("toast.moved", ids.count) : L("toast.skipped", skipped.joined(separator: ", ")))
    }

    /// Sort key keeping the visual order (Dock, then pages, then folders).
    private func order(_ l: Location) -> Int {
        switch l.zone {
        case .dock: return l.index
        case .page(let p): return 1_000 + p * 1_000 + l.index
        case .folder(_, let k): return 1_000_000 + k * 100 + l.index
        }
    }

    func newFolderFromSelection(name: String) {
        let ids = selected.filter(canGoInFolder).sorted { (locate($0).map(order) ?? 0) < (locate($1).map(order) ?? 0) }
        guard !ids.isEmpty else { show(L("toast.selectApps")); return }
        newFolderN += 1
        let fid = "n-\(newFolderN)"
        mutate {
            let loc = locate(ids[0])
            remove(Set(ids))
            let pages = stride(from: 0, to: ids.count, by: folderCap).map { Array(ids[$0..<min($0 + folderCap, ids.count)]) }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            model.folders[fid] = Folder(name: trimmed.isEmpty ? L("dlg.newFolder.default") : trimmed, pages: pages)
            insert(fid, at: loc)
            reflow(locate(fid)?.zone)
            cleanFolders()
        }
        selected.removeAll()
        openFolder = fid
    }

    func ungroup(_ fid: String) {
        guard let folder = model.folders[fid] else { return }
        mutate {
            let loc = locate(fid)
            let kids = folder.pages.flatMap { $0 }
            remove([fid])
            model.folders[fid] = nil
            if let loc, case .page(let p) = loc.zone {
                edit(loc.zone) { $0.insert(contentsOf: kids, at: min(loc.index, $0.count)) }
                reflowHome(from: p)
            } else {
                model.pages.append(kids) // from the Dock there is no room
                reflowHome(from: model.pages.count - 1)
            }
        }
        openFolder = nil
        show(L("toast.ungrouped"))
    }

    func sortFolder(_ fid: String) {
        guard let folder = model.folders[fid] else { return }
        let locale = Locale(identifier: L10n.language)
        let all = folder.pages.flatMap { $0 }.sorted {
            nameOf($0).compare(nameOf($1), options: [.caseInsensitive, .numeric, .diacriticInsensitive], locale: locale) == .orderedAscending
        }
        mutate {
            let pages = stride(from: 0, to: all.count, by: folderCap).map { Array(all[$0..<min($0 + folderCap, all.count)]) }
            model.folders[fid]!.pages = pages.isEmpty ? [[]] : pages
        }
    }

    /// Renames without an undo step per keystroke; `commitRename` records one.
    private var renameBase: HomeModel?
    func renameFolder(_ fid: String, to name: String) {
        if renameBase == nil { renameBase = model }
        model.folders[fid]?.name = String(name.prefix(60))
    }

    func commitRename() {
        if let b = renameBase, b != model { undoStack.append(b) }
        renameBase = nil
    }

    // MARK: feedback

    func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: device

    private func load(_ v: LayoutView) {
        items = v.items
        metrics = v.metrics.columns > 0 ? v.metrics : .iPhone
        model = HomeModel(dock: v.dock, pages: v.pages, folders: v.folders)
        base = model
        sig = v.sig
        count = v.count
        undoStack = []
        selected = []
        openFolder = nil
        phase = .ready
    }

    func connect() async {
        phase = .connecting
        errorText = ""
        if Demo.isOn {
            info = Demo.info
            metrics = .iPhone
            load(Demo.layout())
            return
        }
        do {
            let st = try await Engine.connect()
            info = st.info
            metrics = st.metrics
            load(try await Engine.loadLayout())
        } catch let e as EngineError {
            phase = .failed
            errorText = e.message
        } catch {
            phase = .failed
            errorText = error.localizedDescription
        }
    }

    func save(force: Bool = false) async -> SaveOutcome {
        if Demo.isOn {
            base = model
            show(L("toast.saved"))
            return .ok
        }
        busy = true
        defer { busy = false }
        do {
            let res = try await Engine.save(Payload(dock: model.dock, pages: model.pages, folders: model.folders, sig: sig, force: force))
            if res.conflict == "stale" { return .stale }
            if res.conflict == "changed" { return .changed }
            if let v = res.layout { load(v) }
            show(res.verified ? L("toast.saved") : L("toast.savedAdjusted"))
            return .ok
        } catch let e as EngineError {
            errorText = e.message
            return .failed
        } catch {
            errorText = error.localizedDescription
            return .failed
        }
    }

    func restore(_ name: String) async -> Bool {
        if Demo.isOn { show(L("toast.restored")); return true }
        busy = true
        defer { busy = false }
        do {
            let res = try await Engine.restore(name)
            if let v = res.layout { load(v) }
            show(L("toast.restored"))
            return true
        } catch let e as EngineError {
            errorText = e.message
            return false
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}
