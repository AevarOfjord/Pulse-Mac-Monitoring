import SwiftUI

/// Track the windows hosting dashboards explicitly. Menu bar extras can create
/// visible backing windows with the same title, so title matching is unreliable.
struct DashboardWindowProbe: NSViewRepresentable {
    let monitor: MonitorStore
    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView(); view.monitor = monitor; return view
    }
    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        weak var monitor: MonitorStore?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Task { @MainActor [weak monitor, weak window] in
                if let window { monitor?.trackDashboardWindow(window) }
            }
        }
    }
}
