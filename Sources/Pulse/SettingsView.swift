import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: MonitorStore
    var body: some View {
        Form {
            SwiftUI.Section("Monitoring") {
                Picker("Menu bar reading", selection: $monitor.menuMetric) {
                    ForEach(["CPU", "Memory", "GPU", "Network"], id: \.self) { Text($0).tag($0) }
                }
                Toggle("Reduce sampling when the dashboard is hidden", isOn: $monitor.adaptive)
                Text(monitor.adaptive
                     ? "Hidden: system metrics every 5 seconds and processes every 15 seconds. Visible: your chosen interval and process scans every 5 seconds. Charts stop rendering when all dashboard windows are closed, hidden, or minimized."
                     : "Adaptive sampling is off. System metrics use your chosen interval; processes refresh every 5 seconds. Charts stop rendering when all dashboard windows are closed, hidden, or minimized.").font(.caption).foregroundStyle(.secondary)
                Toggle("Open Pulse at login", isOn: Binding(get: { monitor.loginEnabled }, set: { monitor.setLogin($0) }))
                Text(monitor.loginStatus).font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Sustained pressure alerts") {
                Toggle("Record events and enable notifications", isOn: Binding(get: { monitor.alertsEnabled }, set: { monitor.setAlerts($0) }))
                Picker("Trigger after", selection: $monitor.alertDuration) {
                    Text("30 seconds").tag(30.0); Text("1 minute").tag(60.0); Text("2 minutes").tag(120.0)
                }.disabled(!monitor.alertsEnabled)
                Text("Requires consecutive elevated observations. Each resource has a 15-minute notification cooldown. Sleep and pauses reset the observation window. Notifications hide app and project names. Permission: \(monitor.notificationStatus).")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh status") { Task { await monitor.refreshNotificationStatus() } }
                    if monitor.alertsEnabled {
                        Button("Send test notification", action: monitor.testNotification).disabled(monitor.notificationStatus != "Allowed")
                    }
                }
                if monitor.alertsEnabled, let status = monitor.notificationTestStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            SwiftUI.Section("History & privacy") {
                Toggle("Keep up to 24 hours of history on this Mac", isOn: $monitor.keepHistory)
                Text("Off by default. Retained history includes system metrics and the names of the five largest groups, which may include project basenames. Full executable paths, arguments, and environment values are never stored in history. Turning this off deletes the saved history file; session data remains until cleared or Pulse quits.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Clear all history", action: monitor.clearHistory)
                    Button("Export system metrics…", action: monitor.export)
                }
                Text("Export contains system metrics only, without app or project names. History is saved at most once a minute; quitting can lose the last minute. Pulse makes no network requests.").font(.caption).foregroundStyle(.secondary)
            }
            SwiftUI.Section("Pulse 2.0 preview") {
                Text("Apple silicon · macOS 14+ · Locally signed preview")
                Text("Developer ID signing and notarization require an Apple Developer Program membership. The release scripts support this when one is available.").font(.caption).foregroundStyle(.secondary)
                if let error = monitor.settingsError {
                    Text(error).foregroundStyle(Palette.amber).font(.caption).textSelection(.enabled)
                    Button("Dismiss error") { monitor.settingsError = nil }
                }
            }
        }.formStyle(.grouped).frame(width: 620, height: 690)
            .onAppear { monitor.refreshLoginStatus(); Task { await monitor.refreshNotificationStatus() } }
    }
}
