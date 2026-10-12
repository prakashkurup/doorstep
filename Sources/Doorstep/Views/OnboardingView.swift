import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @Environment(OrderStore.self) private var store
    @State private var connecting = false
    @State private var showGuide = false

    var body: some View {
        if showGuide && !store.auth.hasClientFile {
            SetupGuideView(back: { withAnimation(.snappy) { showGuide = false } })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            intro.transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private var intro: some View {
        VStack(spacing: 22) {
            AppGlyph(size: 60)

            VStack(spacing: 8) {
                Text(store.auth.signedOutByGoogle ? "Google signed you out" : "Every package, one glance")
                    .font(.system(size: 18, weight: .semibold))
                    .kerning(-0.25)
                Text(store.auth.signedOutByGoogle
                     ? "This happens every 7 days while your Google app is in Testing. Reconnect now, then publish the app so it doesn't happen again."
                     : "Doorstep finds shipping emails in your inbox and turns them into a live list of what's on the way.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.auth.signedOutByGoogle {
                VStack(alignment: .leading, spacing: 14) {
                    point("lock", "Read-only access", "It can't send, delete or change any email.")
                    point("desktopcomputer", "Processed on this Mac", "Order details are read on-device. Nothing goes to a server.")
                    point("bell", "A nudge when it matters", "Out for delivery, delivered, or delayed. Nothing else.")
                }
            }

            VStack(spacing: 8) {
                if store.auth.hasClientFile {
                    ConnectButton(title: store.auth.signedOutByGoogle ? "Reconnect Gmail" : "Connect Gmail")
                    if store.auth.signedOutByGoogle {
                        Button("Publish my Google app") {
                            NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/auth/audience")!)
                        }
                        .buttonStyle(NeutralGlassButtonStyle())
                    }
                } else {
                    Button {
                        withAnimation(.snappy) { showGuide = true }
                    } label: {
                        Text("Set up Gmail · about 5 minutes")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.primaryButton)
                }
                if !store.auth.signedOutByGoogle {
                    Button("Preview with sample orders") { store.isSampleMode = true }
                        .buttonStyle(NeutralGlassButtonStyle())
                }
            }
            .padding(.top, 4)

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("Read-only · disconnect anytime in Settings")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 32)
        .padding(.bottom, 22)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.blue)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "Connect Gmail" with a waiting state while the browser sign-in is open.
private struct ConnectButton: View {
    @Environment(OrderStore.self) private var store
    let title: String
    @State private var connecting = false

    var body: some View {
        Button {
            connecting = true
            Task { await store.connect(); connecting = false }
        } label: {
            HStack(spacing: 8) {
                if connecting { ProgressView().controlSize(.small) }
                Text(connecting ? "Finish signing in in your browser…" : title)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.primaryButton)
        .disabled(connecting)
    }
}

// MARK: - Guided setup

/// The Google Cloud steps as a checklist: each opens the exact page, ticks when done,
/// and the client file is picked up from Downloads automatically.
struct SetupGuideView: View {
    @Environment(OrderStore.self) private var store
    let back: () -> Void

    @AppStorage("setupStepsDone") private var doneRaw = ""
    @State private var found: URL?
    @State private var fileError: String?
    @State private var dropTargeted = false

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let url: String
    }

    private let steps = [
        Step(id: 1, title: "Create a project", detail: "Name it anything, like Doorstep, then Create.",
             url: "https://console.cloud.google.com/projectcreate"),
        Step(id: 2, title: "Turn on the Gmail API", detail: "Click Enable. If it says Manage, it's already on.",
             url: "https://console.cloud.google.com/apis/library/gmail.googleapis.com"),
        Step(id: 3, title: "Set up the sign-in screen", detail: "Get started → name \"Doorstep\" → Audience: External → your email → Create.",
             url: "https://console.cloud.google.com/auth/overview"),
        Step(id: 4, title: "Add yourself as a test user", detail: "Test users → Add users → your Gmail address → Save.",
             url: "https://console.cloud.google.com/auth/audience"),
        Step(id: 5, title: "Create a Desktop client", detail: "Create client → Desktop app → Create → Download JSON.",
             url: "https://console.cloud.google.com/auth/clients"),
    ]

    private var done: Set<Int> { Set(doneRaw.split(separator: ",").compactMap { Int($0) }) }
    private var nextStep: Int { steps.first { !done.contains($0.id) }?.id ?? 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Back")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.blue)
                .padding(.leading, 4)
                .padding(.trailing, 10)
                .frame(minHeight: 30)
            }
            .buttonStyle(HoverButtonStyle(cornerRadius: 8))
            .keyboardShortcut(.cancelAction)
            .padding(.leading, 8)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Gmail").font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text("Google asks each person to create a private sign-in for apps that read Gmail. It's free, only you use it, and you do it once.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    ForEach(steps) { step in
                        stepRow(step)
                        if step.id < steps.count { Palette.hairline.frame(height: 0.5).padding(.leading, 44) }
                    }
                }
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                fileCard

                ConnectButton(title: "Connect Gmail")
                    .disabled(!store.auth.hasClientFile)
                    .opacity(store.auth.hasClientFile ? 1 : 0.5)

                Text("Use the Google account whose Gmail you want Doorstep to read.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in use(url) } }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.blue, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        // Watch Downloads only after the download step is opened, so macOS's
        // "access Downloads" prompt shows up with obvious context.
        .task(id: done.contains(5)) {
            guard done.contains(5), !Snapshot.isActive else { return }
            while !Task.isCancelled && !store.auth.hasClientFile {
                if let url = OAuthClient.newestDownload(), url != found {
                    withAnimation(.snappy) { found = url; fileError = nil }
                }
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func stepRow(_ step: Step) -> some View {
        let isDone = done.contains(step.id)
        let isNext = step.id == nextStep
        return HStack(alignment: .top, spacing: 12) {
            Button { toggle(step.id) } label: {
                ZStack {
                    Circle()
                        .fill(isDone ? Palette.green : .clear)
                        .overlay(Circle().strokeBorder(isDone ? .clear : (isNext ? Palette.blue : Color.secondary.opacity(0.4)), lineWidth: 1.5))
                    if isDone {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Text("\(step.id)").font(.system(size: 11, weight: .bold)).foregroundStyle(isNext ? Palette.blue : .secondary)
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Step \(step.id) done. Mark as not done" : "Mark step \(step.id) as done")

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDone ? .secondary : .primary)
                if !isDone {
                    Text(step.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if isNext {
                Button("Open") { open(step) }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.primaryButton)
                    .controlSize(.small)
            } else {
                Button("Open") { open(step) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.snappy(duration: 0.25), value: isDone)
    }

    @ViewBuilder
    private var fileCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: store.auth.hasClientFile ? "checkmark.seal.fill" : "doc.badge.arrow.up")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(store.auth.hasClientFile ? Palette.green : (found != nil ? Palette.blue : .secondary))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                if store.auth.hasClientFile {
                    Text("Client file ready").font(.system(size: 13, weight: .semibold))
                    Text("Now connect and approve read-only access.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else if let found {
                    Text("Found \(found.lastPathComponent)").font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text("In Downloads. Use it?").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else {
                    Text("6  Give Doorstep the file").font(.system(size: 13, weight: .semibold))
                    Text(done.contains(5) ? "Watching Downloads… or drop it here." : "After step 5, it's picked up from Downloads automatically.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fileError {
                    Text(fileError).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if !store.auth.hasClientFile {
                if let found {
                    Button("Use") { use(found) }
                        .buttonStyle(.glassProminent)
                        .tint(Palette.primaryButton)
                        .controlSize(.small)
                } else {
                    Button("Choose…") { choose() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func open(_ step: Step) {
        NSWorkspace.shared.open(URL(string: step.url)!)
        if !done.contains(step.id) { toggle(step.id) }
    }

    private func toggle(_ id: Int) {
        var set = done
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        withAnimation(.snappy(duration: 0.25)) { doneRaw = set.sorted().map(String.init).joined(separator: ",") }
    }

    private func use(_ url: URL) {
        do {
            try store.auth.importClientFile(url)
            fileError = nil
        } catch {
            withAnimation(.snappy) { fileError = error.localizedDescription; found = nil }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = "Choose the client_secret….json you downloaded"
        NSApp.activate()
        panel.begin { response in
            if response == .OK, let url = panel.url { use(url) }
        }
    }
}

struct AppGlyph: View {
    var size: CGFloat = 60

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color(nsColor: NSColor(hex: 0x1F2A44)))
                .overlay(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .overlay(
                    Image(systemName: "shippingbox")
                        .font(.system(size: size * 0.46, weight: .regular))
                        .foregroundStyle(.white)
                )
            Circle()
                .fill(Color(nsColor: NSColor(hex: 0xFFA94D)))
                .frame(width: size * 0.15, height: size * 0.15)
                .padding(size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
