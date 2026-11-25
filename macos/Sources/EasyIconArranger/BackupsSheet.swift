import SwiftUI

struct BackupsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var list: [Backup] = []
    @State private var confirm: Backup?
    @State private var deleting: Backup?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("bk.title")).font(.title2.bold())
            Text(L("bk.body")).foregroundStyle(.secondary)
            List {
                if list.isEmpty {
                    Text(L("bk.none")).foregroundStyle(.secondary)
                }
                ForEach(list) { b in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(date(b.date)).font(.body.weight(.medium))
                            Text(b.name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(L("bk.meta", b.pages, b.items)).font(.caption).foregroundStyle(.secondary)
                        Button(L("bk.restore")) { confirm = b }
                            .disabled(store.busy || store.phase != .ready)
                        Button(role: .destructive) { deleting = b } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(L("bk.delete"))
                        .accessibilityLabel(L("bk.delete"))
                        .disabled(store.busy)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 280)
            HStack {
                Button(L("bk.reveal")) { Engine.revealBackups() }
                Spacer()
                Button(L("dlg.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 480)
        .task { list = Demo.isOn ? Demo.backups : ((try? await Engine.backups()) ?? []) }
        .alert(L("bk.confirm.title"), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { b in
            Button(L("dlg.cancel"), role: .cancel) {}
            Button(L("bk.restore")) {
                Task {
                    if await store.restore(b.name) { dismiss() }
                }
            }
        } message: { b in
            Text([b.name, L("bk.confirm.body"), store.dirty ? L("dlg.discard") : ""].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        .alert(L("bk.delete.title"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { b in
            Button(L("dlg.cancel"), role: .cancel) {}
            Button(L("bk.delete"), role: .destructive) { Task { await delete(b) } }
        } message: { b in
            Text(b.name + "\n\n" + L("bk.delete.body"))
        }
        .alert(L("err.title"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(L("dlg.ok")) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func delete(_ b: Backup) async {
        if !Demo.isOn {
            do {
                try await Engine.deleteBackup(b.name)
            } catch let e as EngineError {
                failure = e.message
                return
            } catch {
                failure = error.localizedDescription
                return
            }
        }
        list.removeAll { $0.id == b.id }
    }

    private func date(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: L10n.language)))
    }
}
