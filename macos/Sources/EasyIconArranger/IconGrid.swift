import SwiftUI
import UniformTypeIdentifiers

struct GridSpan: LayoutValueKey {
    static let defaultValue = CGSize(width: 1, height: 1) // columns x rows
}

/// Places icons row by row on a fixed number of columns, like the iPhone:
/// a widget takes a block of cells (2x2, 4x2, 4x4) at the first place it fits.
struct IconGridLayout: Layout {
    var columns: Int
    var minRows: Int
    var cell: CGSize = UI.cell

    private func positions(_ spans: [CGSize]) -> (cells: [(col: Int, row: Int)], rows: Int) {
        var used = Set<Int>() // row * columns + col
        var out: [(Int, Int)] = []
        var rows = 0
        for s in spans {
            let w = min(max(Int(s.width), 1), columns)
            let h = max(Int(s.height), 1)
            var row = 0
            placing: while true {
                var col = 0
                while col + w <= columns {
                    let fits = (row..<row + h).allSatisfy { r in (col..<col + w).allSatisfy { !used.contains(r * columns + $0) } }
                    if fits {
                        for r in row..<row + h { for c in col..<col + w { used.insert(r * columns + c) } }
                        out.append((col, row))
                        rows = max(rows, row + h)
                        break placing
                    }
                    col += w > 1 ? w : 1
                }
                row += 1
            }
        }
        return (out, rows)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = positions(subviews.map { $0[GridSpan.self] }).rows
        return CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(max(rows, minRows)) * cell.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cells = positions(subviews.map { $0[GridSpan.self] }).cells
        for (i, sv) in subviews.enumerated() {
            let s = sv[GridSpan.self]
            sv.place(
                at: CGPoint(x: bounds.minX + CGFloat(cells[i].col) * cell.width, y: bounds.minY + CGFloat(cells[i].row) * cell.height),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: s.width * cell.width, height: s.height * cell.height)
            )
        }
    }
}

/// One drop zone (a Home Screen page, a folder page or the Dock) with its icons.
struct IconGrid: View {
    @Environment(AppStore.self) private var store
    let zone: Zone
    let ids: [String]
    let columns: Int
    let rows: Int

    var body: some View {
        IconGridLayout(columns: columns, minRows: rows) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                let s = store.span(id)
                TileView(id: id, zone: zone, index: index)
                    .layoutValue(key: GridSpan.self, value: CGSize(width: s.cols, height: s.rows))
            }
        }
        .contentShape(.rect)
        .onDrop(of: [.text], delegate: GridDropDelegate(store: store, zone: zone))
        .animation(.snappy(duration: 0.22), value: ids)
    }
}

/// Dropping on empty space of a zone appends the icon at the end.
@MainActor
struct GridDropDelegate: DropDelegate {
    let store: AppStore
    let zone: Zone

    func validateDrop(info: DropInfo) -> Bool { store.accepts(store.dragging, into: zone) }

    func dropEntered(info: DropInfo) {
        store.insertHint = nil
        store.hoverFolder = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = store.dragging, store.accepts(id, into: zone) else { return false }
        store.move(id, to: zone, at: store.list(zone).count)
        store.dragging = nil
        return true
    }
}
