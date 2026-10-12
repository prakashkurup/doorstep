import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(OrderStore.self) private var store
    @State private var connecting = false

    var body: some View {
        VStack(spacing: 22) {
            AppGlyph(size: 60)

            VStack(spacing: 8) {
                Text("Every package, one glance")
                    .font(.system(size: 18, weight: .semibold))
                    .kerning(-0.25)
                Text("Doorstep finds shipping emails in your inbox and turns them into a live list of what's on the way.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                point("lock", "Read-only access", "It can't send, delete or change any email.")
                point("desktopcomputer", "Processed on this Mac", "Order details are read on-device. Nothing goes to a server.")
                point("bell", "A nudge when it matters", "Out for delivery, delivered, or delayed. Nothing else.")
            }

            VStack(spacing: 8) {
                if store.auth.hasClientFile {
                    Button {
                        connecting = true
                        Task { await store.connect(); connecting = false }
                    } label: {
                        if connecting {
                            HStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white); Text("Waiting for Google…") }
                        } else {
                            Text("Connect Gmail")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 40))
                    .disabled(connecting)
                } else {
                    missingClientNotice
                }
                Button("Preview with sample orders") { store.isSampleMode = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.red)
                    .multilineTextAlignment(.center)
            } else {
                Text("Disconnect anytime in Settings.")
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

    private var missingClientNotice: some View {
        VStack(spacing: 8) {
            Text("Add your Google client file to connect Gmail. The README has the 5-minute setup.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show folder") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
            }
            .buttonStyle(PrimaryButtonStyle(height: 36))
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
