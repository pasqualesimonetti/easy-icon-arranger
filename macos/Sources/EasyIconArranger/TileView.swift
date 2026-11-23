import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One icon: app, folder, widget or web link. Draggable and a drop target.
struct TileView: View {
    @Environment(AppStore.self) private var store
    let id: String
    let zone: Zone
    let index: Int

    var body: some View {
        let span = store.span(id)
        let size = CGSize(width: CGFloat(span.cols) * UI.cell.width, height: CGFloat(span.rows) * UI.cell.height)
        let folder = store.model.folders[id]
        let item = store.items[id]
        let selected = store.selected.contains(id)
        let dimmed = store.matches.map { !$0.contains(id) } ?? false
        let hint = store.insertHint?.id == id ? store.insertHint : nil

        VStack(spacing: 5) {
            Group {
                if let folder {
                    FolderIconView(folder: folder)
                } else if item?.isWidget == true {
                    widget(item, size: size)
                } else {
                    AppIconView(item: item)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: (item?.isWidget == true ? 22 : UI.icon * UI.corner) + 3, style: .continuous)
                    .strokeBorder(ringColor(selected: selected), style: StrokeStyle(lineWidth: 3, dash: store.hoverFolder == id ? [6, 4] : []))
                    .padding(-4)
                    .opacity(selected || store.openFolder == id || store.hoverFolder == id || (store.matches?.contains(id) ?? false) ? 1 : 0)
            }
            .overlay(alignment: .topTrailing) {
                if folder != nil {
                    Text("\(store.folderCount(id))")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(.secondary, in: .capsule)
                        .offset(x: 7, y: -6)
                }
            }
            .scaleEffect(store.hoverFolder == id ? 1.14 : 1)
            .animation(.snappy(duration: 0.15), value: store.hoverFolder == id)

            Text(store.nameOf(id))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: UI.cell.width - 6)
        }
        .padding(.top, 6)
        .frame(width: size.width, height: size.height, alignment: .top)
        .overlay(alignment: hint?.after == true ? .trailing : .leading) {
            if hint != nil {
                Capsule().fill(Color.accentColor).frame(width: 3, height: UI.icon).padding(.top, 6)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .opacity(dimmed ? 0.18 : 1)
        .contentShape(.rect)
        .onTapGesture { tap(isFolder: folder != nil) }
        .onDrag {
            store.dragging = id
            return NSItemProvider(object: id as NSString)
        } preview: {
            if let folder { FolderIconView(folder: folder).environment(store) } else { AppIconView(item: item) }
        }
        .onDrop(of: [.text], delegate: TileDropDelegate(store: store, target: id, zone: zone, index: index, size: size))
        .contextMenu { menu(isFolder: folder != nil) }
        .help(tooltip(item: item, isFolder: folder != nil))
        .accessibilityLabel(store.nameOf(id))
    }

    private func ringColor(selected: Bool) -> Color {
        if selected || store.hoverFolder == id { return .accentColor }
        if store.openFolder == id { return .yellow }
        return .yellow.opacity(0.9) // search hit
    }

    @ViewBuilder private func widget(_ item: Item?, size: CGSize) -> some View {
        VStack(spacing: 6) {
            AppIconView(item: item, size: 40)
            Text(L("item.widget", L("size." + (item?.size ?? "small"))))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: size.width - 12, height: size.height - 26)
        .background(.quaternary, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func tap(isFolder: Bool) {
        if isFolder && !NSEvent.modifierFlags.contains(.command) {
            store.openFolder = store.openFolder == id ? nil : id
        } else {
            store.toggleSelect(id)
        }
    }

    private func tooltip(item: Item?, isFolder: Bool) -> String {
        if isFolder { return "\(store.nameOf(id)) (\(store.folderCount(id)))" }
        if item?.type == "webclip" { return "\(store.nameOf(id))\n\(L("item.webclip"))" }
        return [store.nameOf(id), item?.key].compactMap { $0 }.joined(separator: "\n")
    }

    @ViewBuilder private func menu(isFolder: Bool) -> some View {
        if isFolder {
            Button(L("folder.open")) { store.openFolder = id }
            Button(L("folder.ungroup")) { store.ungroup(id) }
            Divider()
        }
        Button(store.selected.contains(id) ? L("sel.deselect") : L("sel.select")) { store.toggleSelect(id) }
        MoveToMenu { target in
            if !store.selected.contains(id) { store.selected = [id] }
            store.moveSelected(to: target)
        }
    }
}

/// "Move to" destinations: Dock, pages, a new page and folders.
struct MoveToMenu: View {
    @Environment(AppStore.self) private var store
    let action: (AppStore.Target) -> Void

    var body: some View {
        Menu(L("sel.moveTo")) {
            Button(L("sel.dock")) { action(.dock) }
            ForEach(store.model.pages.indices, id: \.self) { i in
                Button(L("sel.page", i + 1, store.pageSlots(store.model.pages[i]), store.pageCap)) { action(.page(i)) }
            }
            Button(L("sel.newPage")) { action(.newPage) }
            let folders = store.model.folders.keys
                .filter { store.locate($0) != nil }
                .sorted { store.nameOf($0).localizedStandardCompare(store.nameOf($1)) == .orderedAscending }
            if !folders.isEmpty {
                Divider()
                Section(L("sel.folders")) {
                    ForEach(folders, id: \.self) { fid in
                        Button(store.nameOf(fid)) { action(.folder(fid)) }
                    }
                }
            }
        }
    }
}

/// Dropping on an icon: before or after it, or into it when it is a folder
/// and the pointer is on its centre (holding there opens the folder).
@MainActor
struct TileDropDelegate: DropDelegate {
    let store: AppStore
    let target: String
    let zone: Zone
    let index: Int
    let size: CGSize

    private var folderTarget: Bool {
        if case .folder = zone { return false }
        return store.isFolder(target)
    }

    private func inCentre(_ p: CGPoint) -> Bool {
        let x0 = (size.width - UI.icon) / 2
        let icon = CGRect(x: x0, y: 6, width: UI.icon, height: UI.icon)
        return icon.insetBy(dx: UI.icon * 0.15, dy: UI.icon * 0.1).contains(p)
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard let d = store.dragging, d != target else { return false }
        return store.accepts(d, into: zone) || (folderTarget && store.canGoInFolder(d))
    }

    func dropEntered(info: DropInfo) { update(info.location) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info.location)
        return DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func dropExited(info: DropInfo) {
        if store.hoverFolder == target { store.hoverFolder = nil }
        if store.insertHint?.id == target { store.insertHint = nil }
    }

    private func update(_ p: CGPoint) {
        guard let d = store.dragging, d != target else { return }
        if folderTarget && store.canGoInFolder(d) && inCentre(p) {
            store.insertHint = nil
            if store.hoverFolder != target {
                store.hoverFolder = target
                let store = self.store, target = self.target
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    if store.hoverFolder == target && store.dragging != nil { store.openFolder = target }
                }
            }
        } else {
            if store.hoverFolder == target { store.hoverFolder = nil }
            if store.accepts(d, into: zone) {
                let after = p.x > size.width / 2
                if store.insertHint?.id != target || store.insertHint?.after != after { store.insertHint = (target, after) }
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let d = store.dragging else { return false }
        defer {
            store.hoverFolder = nil
            store.insertHint = nil
            store.dragging = nil
        }
        if folderTarget && store.canGoInFolder(d) && inCentre(info.location) {
            store.drop(d, intoFolder: target)
            return true
        }
        guard store.accepts(d, into: zone) else { return false }
        store.move(d, to: zone, at: index + (info.location.x > size.width / 2 ? 1 : 0))
        return true
    }
}
