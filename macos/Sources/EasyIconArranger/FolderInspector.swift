import SwiftUI

/// The open folder, page by page, with the iPhone folder grid (3x3 on iPhone).
struct FolderInspector: View {
    @Environment(AppStore.self) private var store
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let fid = store.openFolder, let folder = store.model.folders[fid] {
            let total = folder.pages.reduce(0) { $0 + $1.count }
            let usedPages = folder.pages.filter { !$0.isEmpty }.count
            VStack(alignment: .leading, spacing: 12) {
                TextField(L("folder.name"), text: Binding(
                    get: { store.model.folders[fid]?.name ?? "" },
                    set: { store.renameFolder(fid, to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.title3.weight(.semibold))
                .focused($nameFocused)
                .onSubmit { store.commitRename() }
                .onChange(of: nameFocused) { _, focused in if !focused { store.commitRename() } }

                HStack {
                    Button(L("folder.sort")) { store.sortFolder(fid) }
                    Button(L("folder.ungroup")) { store.ungroup(fid) }
                    Spacer()
                    Text(usedPages == 1 ? L("folder.summaryOne", total) : L("folder.summary", total, usedPages))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(folder.pages.indices, id: \.self) { k in
                            folderPage(fid: fid, k: k, ids: folder.pages[k], title: L("folder.page", k + 1))
                        }
                        if usedPages < store.metrics.folderMaxPages {
                            folderPage(fid: fid, k: folder.pages.count, ids: [], title: L("folder.newPage"))
                                .overlay {
                                    Text(L("folder.dropNew")).font(.caption).foregroundStyle(.secondary).allowsHitTesting(false)
                                        .padding(.top, 16)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Text(L("folder.hint", store.folderCap)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func folderPage(fid: String, k: Int, ids: [String], title: String) -> some View {
        let over = ids.count > store.folderCap
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if !ids.isEmpty {
                    Text("\(ids.count)/\(store.folderCap)").monospacedDigit().foregroundStyle(over ? .red : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            IconGrid(zone: .folder(fid, k), ids: ids, columns: store.metrics.folderColumns, rows: store.metrics.folderRows)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(ids.isEmpty ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary),
                            in: .rect(cornerRadius: 26, style: .continuous))
                .overlay {
                    if ids.isEmpty {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    } else if over {
                        RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.red, lineWidth: 2)
                    }
                }
        }
    }
}
