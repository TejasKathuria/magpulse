import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject var manager: MagpulseManager

    public var body: some View {
        VStack {
            // Status Header
            HStack {
                Circle()
                    .fill(manager.isMasterEnabled && manager.isPulsing ? manager.selectedColor.displayColor : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.vertical, 4)

            Divider()

            // Toggle Master
            Button(action: {
                manager.isMasterEnabled.toggle()
            }) {
                HStack {
                    Image(systemName: manager.isMasterEnabled ? "checkmark.circle.fill" : "circle")
                    Text(manager.isMasterEnabled ? "Magpulse: Enabled" : "Magpulse: Disabled")
                }
            }

            // Quick Color switch
            Menu("Color: \(manager.selectedColor.rawValue)") {
                Button("Amber / Orange") {
                    manager.selectedColor = .amber
                }
                Button("Green") {
                    manager.selectedColor = .green
                }
            }

            // Test Pulse
            Button("Test Pulse (5s)") {
                manager.triggerTestPulse(duration: 5.0)
            }
            .disabled(!manager.isMasterEnabled)

            Divider()

            // Open Window
            Button("Open Magpulse Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            // Quit
            Button("Quit Magpulse") {
                manager.stopPulsing()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var statusText: String {
        if !manager.isMasterEnabled {
            return "Magpulse Disabled"
        }
        if manager.isTesting {
            return "Testing MagSafe LED..."
        }
        if manager.isPulsing {
            if let agent = manager.activeAgentId {
                return "Active: \(agent)"
            }
            return "Pulsing MagSafe LED"
        }
        return "Idle (Monitoring)"
    }
}

