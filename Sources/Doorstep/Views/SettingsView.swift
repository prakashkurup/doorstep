import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(OrderStore.self) private var store
    let back: () -> Void

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Deliveries")
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

            FittedScroll(maxHeight: 640) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)

                group {
                    row("Gmail") {
                        if store.isConnected {
                            Text(store.accountEmail ?? "Connected").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("Not connected").foregroundStyle(.secondary)
                        }
                    }
                    divider
                    if store.isConnected {
                        row("") {
                            Button("Disconnect") { store.signOut() }
                                .buttonStyle(.link)
                                .foregroundStyle(Palette.red)
                        }
                    } else {
                        row("") {
                            Button("Connect Gmail") { Task { await store.connect() } }
                                .buttonStyle(.link)
                                .disabled(!store.auth.hasClientFile)
                        }
                    }
                }

                LiveTrackingSettings()

                group {
                    row("Notifications") {
                        Toggle("", isOn: $store.notificationsEnabled).toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                    divider
                    row("Open at login") {
                        Toggle("", isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                            .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    }
                    if !store.isConnected {
                        divider
                        row("Sample orders") {
                            Toggle("", isOn: $store.isSampleMode).toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                    }
                }

                Text("Checks Gmail every 15 minutes and when your Mac wakes. Emails are read on this Mac only.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Quit Doorstep") { NSApp.terminate(nil) }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            }
        }
    }

    private var divider: some View { Palette.hairline.frame(height: 0.5) }

    private func group<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0, content: content)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 0.5))
    }

    private func row<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 12) {
            if !label.isEmpty { Text(label) }
            Spacer(minLength: 8)
            value()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
    }
}
