import SwiftUI

/// One row per carrier. Each is optional: connect only the carriers you get packages from.
struct LiveTrackingSettings: View {
    @Environment(OrderStore.self) private var store
    @State private var editing: String?
    @State private var idText = ""
    @State private var secretText = ""
    @State private var saving = false
    @State private var error: String?

    private let fallbackID = "17track"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Live tracking").padding(.horizontal, -8)
            VStack(spacing: 0) {
                ForEach(Array(CarrierCredentials.Kind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Palette.hairline.frame(height: 0.5) }
                    carrierRow(kind)
                }
                Palette.hairline.frame(height: 0.5)
                fallbackRow
            }
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))

            Text(note)
                .font(.system(size: 11.5))
                .foregroundStyle(store.liveError == nil ? .secondary : Palette.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var note: String {
        if let e = store.liveError { return e }
        if store.isLiveTrackingOn {
            var text = "Following \(store.liveTrackedCount) package\(store.liveTrackedCount == 1 ? "" : "s") live."
            if let q = store.liveQuota { text += " 17TRACK: \(q.total - q.used) of \(q.total) numbers left." }
            return text
        }
        return "Optional. Add free developer credentials for the carriers you use; the rest keep tracking from email. Amazon's own numbers can't be tracked outside Amazon."
    }

    @ViewBuilder
    private func carrierRow(_ kind: CarrierCredentials.Kind) -> some View {
        let connected = store.connectedCarriers.contains(kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind.name).font(.system(size: 13))
                Spacer()
                if connected {
                    Label("Connected", systemImage: "checkmark").labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.green)
                    Button("Remove") { store.disconnectCarrier(kind) }
                        .buttonStyle(.link).font(.system(size: 12)).foregroundStyle(Palette.red)
                } else if editing != kind.id {
                    Button("Connect") { startEditing(kind.id) }.buttonStyle(.link).font(.system(size: 12))
                }
            }
            if editing == kind.id, !connected {
                editor(idLabel: kind.idLabel, secretLabel: kind.needsSecret ? kind.secretLabel : nil, signup: kind.signupURL,
                       signupText: "Get free \(kind.name) credentials") {
                    await store.connectCarrier(kind, id: idText, secret: kind.needsSecret ? secretText : nil)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var fallbackRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Other carriers").font(.system(size: 13))
                    Text("via 17TRACK").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if store.hasLiveTrackingKey {
                    Label("Connected", systemImage: "checkmark").labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.green)
                    Button("Remove") { store.removeLiveTrackingKey() }
                        .buttonStyle(.link).font(.system(size: 12)).foregroundStyle(Palette.red)
                } else if editing != fallbackID {
                    Button("Connect") { startEditing(fallbackID) }.buttonStyle(.link).font(.system(size: 12))
                }
            }
            if editing == fallbackID, !store.hasLiveTrackingKey {
                editor(idLabel: "17TRACK API key", secretLabel: nil, signup: URL(string: "https://api.17track.net")!,
                       signupText: "Get a 17TRACK key (200 free numbers)") {
                    await store.saveLiveTrackingKey(idText)
                    return store.liveError
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func editor(idLabel: String, secretLabel: String?, signup: URL, signupText: String,
                        save: @escaping () async -> String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(idLabel, text: $idText)
                .textFieldStyle(.roundedBorder).font(.system(size: 12))
            if let secretLabel {
                SecureField(secretLabel, text: $secretText)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
            }
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Palette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link(signupText, destination: signup).font(.system(size: 11.5, weight: .medium))
                Spacer()
                Button("Cancel") { editing = nil; error = nil }
                    .buttonStyle(.link).font(.system(size: 12)).foregroundStyle(.secondary)
                Button(saving ? "Checking…" : "Save") {
                    saving = true
                    error = nil
                    Task {
                        let message = await save()
                        saving = false
                        if let message { error = message } else { editing = nil; idText = ""; secretText = "" }
                    }
                }
                .disabled(idText.isEmpty || (secretLabel != nil && secretText.isEmpty) || saving)
            }
        }
    }

    private func startEditing(_ id: String) {
        editing = id
        idText = ""
        secretText = ""
        error = nil
    }
}
