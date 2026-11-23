import AppKit
import SwiftUI

enum UI {
    static let cell = CGSize(width: 82, height: 98)
    static let icon: CGFloat = 60
    static let corner: CGFloat = 0.225 // iOS icon corner ratio
}

/// Icons come from the iPhone through the Go engine (cached on disk there);
/// this keeps decoded images in memory and limits parallel fetches.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var images: [String: NSImage] = [:]
    private var failed: Set<String> = []
    private var waiting: [String: [CheckedContinuation<NSImage?, Never>]] = [:]
    private let queue = DispatchQueue(label: "icons", qos: .userInitiated, attributes: .concurrent)
    private let gate = DispatchSemaphore(value: 4)

    func cached(_ key: String) -> NSImage? { images[key] }

    func image(for key: String) async -> NSImage? {
        if let img = images[key] { return img }
        if failed.contains(key) { return nil }
        if waiting[key] != nil {
            return await withCheckedContinuation { waiting[key]?.append($0) }
        }
        waiting[key] = []
        let gate = self.gate
        let data: Data? = await withCheckedContinuation { cont in
            queue.async {
                gate.wait()
                defer { gate.signal() }
                let path = Engine.iconPath(key)
                cont.resume(returning: path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) })
            }
        }
        let img = data.flatMap(NSImage.init(data:))
        if let img { images[key] = img } else { failed.insert(key) }
        for c in waiting.removeValue(forKey: key) ?? [] { c.resume(returning: img) }
        return img
    }

    func reset() {
        images.removeAll()
        failed.removeAll()
    }
}

/// An app icon with the iOS rounded shape; a coloured initial when there is no icon.
struct AppIconView: View {
    let item: Item?
    var size: CGFloat = UI.icon
    @State private var image: NSImage?

    init(item: Item?, size: CGFloat = UI.icon) {
        self.item = item
        self.size = size
        _image = State(initialValue: item?.key.flatMap { IconCache.shared.cached($0) })
    }

    var body: some View {
        Group {
            if Demo.isOn, let key = item?.key, let s = Demo.symbol(for: key) {
                DemoIcon(symbol: s.name, hue: s.hue, size: size)
            } else if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                let name = item?.name.trimmingCharacters(in: .whitespaces) ?? "?"
                ZStack {
                    // stable colour per name (String.hashValue changes at every launch)
                    Color(hue: Double(name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360,
                          saturation: 0.45, brightness: 0.8)
                    Text(String(name.first ?? "?").uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * UI.corner, style: .continuous))
        .task(id: item?.key) {
            guard !Demo.isOn, let key = item?.key, image == nil else { return }
            image = await IconCache.shared.image(for: key)
        }
    }
}

/// A folder as on the iPhone: its first page in a small grid (3x3 on iPhone).
struct FolderIconView: View {
    @Environment(AppStore.self) private var store
    let folder: Folder

    var body: some View {
        let cols = store.metrics.folderColumns
        let cap = store.folderCap
        let first = Array((folder.pages.first { !$0.isEmpty } ?? []).prefix(cap))
        let mini = (UI.icon - 14 - CGFloat(cols - 1) * 3) / CGFloat(cols)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(mini), spacing: 3), count: cols), spacing: 3) {
            ForEach(first, id: \.self) { id in
                AppIconView(item: store.items[id], size: mini)
            }
        }
        .frame(width: UI.icon - 14, height: UI.icon - 14, alignment: .top)
        .padding(7)
        .frame(width: UI.icon, height: UI.icon)
        .background(.quaternary, in: .rect(cornerRadius: UI.icon * UI.corner, style: .continuous))
    }
}
