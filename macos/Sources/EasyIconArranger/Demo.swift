import AppKit
import SwiftUI

/// Demo mode (`-demoMode YES` at launch): a made-up Home Screen with invented
/// apps and SF Symbol icons, so screenshots never show a real phone. No device
/// is contacted and nothing is written.
enum Demo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demoMode") }

    static let info = DeviceInfo(name: "iPhone", ios: "27.2", model: "iPhone", deviceClass: "iPhone", udid: "", usb: true)

    /// name, SF Symbol, hue (0-1)
    private typealias App = (String, String, Double)

    private static let dock: [App] = [
        ("Phone", "phone.fill", 0.36), ("Messages", "message.fill", 0.33),
        ("Browser", "safari.fill", 0.58), ("Music", "music.note", 0.97),
    ]
    private static let home: [App] = [
        ("Calendar", "calendar", 0.0), ("Photos", "photo.on.rectangle", 0.12),
        ("Camera", "camera.fill", 0.6), ("Weather", "cloud.sun.fill", 0.56),
        ("Maps", "map.fill", 0.3), ("Notes", "note.text", 0.14),
        ("Clock", "clock.fill", 0.7), ("Mail", "envelope.fill", 0.6),
    ]
    private static let folders: [(String, [App])] = [
        ("Social", [("Chatter", "bubble.left.and.bubble.right.fill", 0.55), ("Snapline", "camera.aperture", 0.85),
                    ("Circle", "person.3.fill", 0.62), ("Forum", "text.bubble.fill", 0.05),
                    ("Meetup", "figure.2", 0.45), ("Pixel Feed", "square.grid.3x3.fill", 0.9)]),
        ("Productivity", [("Tasks", "checklist", 0.6), ("Docs", "doc.text.fill", 0.58), ("Sheets", "tablecells.fill", 0.35),
                          ("Slides", "rectangle.on.rectangle", 0.1), ("Drive", "externaldrive.fill", 0.15),
                          ("Notebook", "book.closed.fill", 0.75), ("Focus", "timer", 0.0), ("Scan", "doc.viewfinder", 0.5),
                          ("Sign", "signature", 0.68), ("Mind Map", "point.3.connected.trianglepath.dotted", 0.8),
                          ("Inbox Zero", "tray.full.fill", 0.55)]),
        ("Travel", [("Trains", "tram.fill", 0.0), ("Flights", "airplane", 0.58), ("Stays", "bed.double.fill", 0.95),
                    ("Translate", "character.bubble.fill", 0.62), ("Rides", "car.fill", 0.1)]),
        ("Finance", [("Wallet", "wallet.pass.fill", 0.1), ("Bank", "building.columns.fill", 0.6),
                     ("Budget", "chart.pie.fill", 0.35), ("Invest", "chart.line.uptrend.xyaxis", 0.4),
                     ("Pay", "creditcard.fill", 0.75)]),
        ("Health", [("Steps", "figure.walk", 0.3), ("Sleep", "bed.double.fill", 0.68),
                    ("Yoga", "figure.mind.and.body", 0.8), ("Water", "drop.fill", 0.55)]),
        ("Utilities", [("Calculator", "plus.forwardslash.minus", 0.08), ("Files", "folder.fill", 0.58),
                       ("Compass", "safari", 0.0), ("Measure", "ruler.fill", 0.12), ("Voice Memos", "waveform", 0.97),
                       ("Flashlight", "flashlight.on.fill", 0.15), ("Settings", "gearshape.fill", 0.0)]),
        ("Entertainment", [("Movies", "film.fill", 0.0), ("Podcasts", "mic.fill", 0.78), ("Books", "book.fill", 0.08),
                           ("Games", "gamecontroller.fill", 0.45), ("Radio", "radio.fill", 0.95)]),
        ("Shopping", [("Market", "cart.fill", 0.1), ("Fashion", "tshirt.fill", 0.88), ("Groceries", "basket.fill", 0.3)]),
    ]
    private static let page2: [App] = [
        ("Recipes", "fork.knife", 0.05), ("Plants", "leaf.fill", 0.33), ("Garage", "wrench.and.screwdriver.fill", 0.6),
        ("Pets", "pawprint.fill", 0.1), ("Learn", "graduationcap.fill", 0.65),
    ]

    nonisolated(unsafe) private static var symbols: [String: (String, Double)] = [:]

    static let backups = [
        Backup(name: "20261123_101500_before-save.plist", date: "2026-11-23T10:15:00Z", pages: 2, items: 64),
        Backup(name: "20261120_183000_before-save.plist", date: "2026-11-20T18:30:00Z", pages: 3, items: 61),
        Backup(name: "20261118_090500_before-restore.plist", date: "2026-11-18T09:05:00Z", pages: 3, items: 61),
    ]

    static func symbol(for key: String) -> (name: String, hue: Double)? {
        symbols[key].map { (name: $0.0, hue: $0.1) }
    }

    static func layout() -> LayoutView {
        var items: [String: Item] = [:]
        var n = 0
        func add(_ a: App, type: String = "app", size: String? = nil) -> String {
            n += 1
            let id = "demo-\(n)"
            let key = "demo.\(a.0.lowercased().replacingOccurrences(of: " ", with: "-"))"
            symbols[key] = (a.1, a.2)
            items[id] = Item(id: id, type: type, name: a.0, key: key, size: size, widget: nil)
            return id
        }
        let dockIDs = dock.map { add($0) }
        var folderMap: [String: Folder] = [:]
        var page1: [String] = []
        for (name, apps) in folders {
            n += 1
            let fid = "demo-f\(n)"
            let ids = apps.map { add($0) }
            folderMap[fid] = Folder(name: name, pages: stride(from: 0, to: ids.count, by: 9).map { Array(ids[$0..<min($0 + 9, ids.count)]) })
            page1.append(fid)
        }
        page1 += home.map { add($0) }
        var page2IDs = [add(("Weather", "cloud.sun.fill", 0.56), type: "widget", size: "medium")]
        page2IDs += page2.map { add($0) }
        let count = items.count + folderMap.count
        return LayoutView(items: items, folders: folderMap, dock: dockIDs, pages: [page1, page2IDs],
                          sig: "demo", count: count, metrics: .iPhone)
    }
}

/// Icon drawn for demo apps.
struct DemoIcon: View {
    let symbol: String
    let hue: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                    Color(hue: hue, saturation: 0.75, brightness: 0.72)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Brand colours (from the app icon, also used by the website).
enum Brand {
    static let blue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)   // #2563EB
    static let violet = Color(red: 94 / 255, green: 64 / 255, blue: 214 / 255) // #5E40D6
    static let amber = Color(red: 1, green: 176 / 255, blue: 32 / 255)         // #FFB020

    /// Window appearance: "system" (default), "light" or "dark", stored in
    /// UserDefaults ("appearance"). `-appearance light` at launch also works.
    static let appearanceKey = "appearance"

    @MainActor static func applyAppearance(_ value: String? = nil) {
        switch value ?? UserDefaults.standard.string(forKey: appearanceKey) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static func appearanceSymbol(_ value: String) -> String {
        switch value {
        case "light": "sun.max"
        case "dark": "moon"
        default: "circle.lefthalf.filled"
        }
    }
}
