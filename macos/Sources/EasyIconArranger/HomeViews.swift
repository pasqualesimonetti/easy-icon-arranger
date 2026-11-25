import SwiftUI

/// All Home Screen pages side by side, plus an empty page to drop into.
struct HomeScreenView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let pageWidth = CGFloat(store.metrics.columns) * UI.cell.width + 28
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: pageWidth, maximum: pageWidth), spacing: 20, alignment: .top)],
                      alignment: .leading, spacing: 20) {
                ForEach(store.model.pages.indices, id: \.self) { i in
                    PageCard(index: i)
                }
                if store.model.pages.filter({ !$0.isEmpty }).count < store.metrics.maxPages {
                    NewPageCard()
                }
            }
            .padding(20)
            .padding(.bottom, 190) // room for the Dock
        }
        .scrollIndicators(.automatic)
    }
}

struct PageCard: View {
    @Environment(AppStore.self) private var store
    let index: Int

    var body: some View {
        let page = store.model.pages[index]
        let used = store.pageSlots(page)
        let over = used > store.pageCap
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L("page.title", index + 1)).font(.headline)
                Spacer()
                Text("\(used)/\(store.pageCap)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(over ? .red : .secondary)
                    .fontWeight(over ? .semibold : .regular)
                Menu {
                    Button(L("page.moveLeft")) { store.movePage(index, by: -1) }.disabled(index == 0)
                    Button(L("page.moveRight")) { store.movePage(index, by: 1) }.disabled(index >= store.model.pages.count - 1)
                    Divider()
                    Button(L("page.delete"), role: .destructive) { store.deletePage(index) }.disabled(!page.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 4)
            IconGrid(zone: .page(index), ids: page, columns: store.metrics.columns, rows: store.metrics.rows)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(over ? Color.red : Color.primary.opacity(0.08), lineWidth: over ? 2 : 1)
        }
    }
}

/// The page after the last one: dropping an icon here starts a new page.
struct NewPageCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("page.new")).font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button { store.addPage() } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
            IconGrid(zone: .page(store.model.pages.count), ids: [], columns: store.metrics.columns, rows: store.metrics.rows)
                .overlay {
                    Text(L("page.dropNew"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(30)
                        .allowsHitTesting(false)
                }
        }
        .padding(14)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
    }
}

/// The Dock, floating at the bottom in Liquid Glass.
struct DockView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let over = store.model.dock.count > store.metrics.dockMax
        VStack(spacing: 2) {
            Text("\(L("dock.title"))  \(store.model.dock.count)/\(store.metrics.dockMax)")
                .font(.caption2)
                .foregroundStyle(over ? .red : .secondary)
            IconGrid(zone: .dock, ids: store.model.dock, columns: store.metrics.dockMax, rows: 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
    }
}

/// Appears when icons are selected: move them or make a folder.
struct SelectionBar: View {
    @Environment(AppStore.self) private var store
    @Binding var askFolderName: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(L("sel.count", store.selected.count)).font(.callout.weight(.semibold))
            MoveToMenu { store.moveSelected(to: $0) }
                .fixedSize()
            Button(L("sel.newFolder")) { askFolderName = true }
            Button(L("sel.clear")) { store.selected.removeAll() }
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Brand.blue.opacity(0.15)), in: .capsule)
    }
}
