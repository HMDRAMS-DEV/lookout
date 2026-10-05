import ServiceManagement
import SwiftUI

/// One page, in the native grouped style.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cursorConnected = Hooks.cursorInstalled
    @State private var cursorError: String?
    @AppStorage(Keys.notifyDone) private var notifyDone = true
    @AppStorage(Keys.notifyWaiting) private var notifyWaiting = true
    @AppStorage(Keys.sound) private var sound = true
    @AppStorage(Keys.minTurn) private var minTurn = 10
    @AppStorage(Keys.keepHours) private var keepHours = 8

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Lookout at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Picker("Keep finished sessions for", selection: $keepHours) {
                    Text("1 hour").tag(1)
                    Text("4 hours").tag(4)
                    Text("8 hours").tag(8)
                    Text("1 day").tag(24)
                }
            }

            Section("Notify me") {
                Toggle("When an agent finishes", isOn: $notifyDone)
                Toggle("When an agent needs me", isOn: $notifyWaiting)
                Picker("Skip turns shorter than", selection: $minTurn) {
                    Text("Never skip").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
                .disabled(!notifyDone)
                Toggle("Play a sound", isOn: $sound)
            }

            Section {
                LabeledContent("Claude Code") { automatic }
                LabeledContent("Codex") { automatic }
                LabeledContent("Cursor") {
                    if cursorConnected {
                        HStack {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Button("Disconnect") { setCursor(false) }
                        }
                    } else {
                        Button("Connect") { setCursor(true) }
                    }
                }
            } header: {
                Text("Agents")
            } footer: {
                Text(cursorError ?? "Claude Code and Codex record their state on disk, so Lookout reads it directly. Cursor doesn't, so Lookout adds a hook to ~/.cursor/hooks.json. Cursor picks it up after a restart.")
                    .foregroundStyle(cursorError == nil ? .secondary : Color.red)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .frame(width: 460, height: 560)
        .onAppear { cursorConnected = Hooks.cursorInstalled }
    }

    private var automatic: some View {
        Label("Automatic", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.secondary)
    }

    private func setCursor(_ on: Bool) {
        do {
            try on ? Hooks.installCursor() : Hooks.removeCursor()
            cursorError = nil
        } catch {
            cursorError = "Couldn't update ~/.cursor/hooks.json: \(error.localizedDescription)"
        }
        cursorConnected = Hooks.cursorInstalled
    }
}
