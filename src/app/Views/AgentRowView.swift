import SwiftUI

public struct AgentRowView: View {
    @ObservedObject var manager: MagpulseManager
    let agent: MonitoredAgent

    public init(manager: MagpulseManager, agent: MonitoredAgent) {
        self.manager = manager
        self.agent = agent
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Text only (no icon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(agent.isEnabled ? .primary : .secondary)

                    // Active badge if currently triggering pulse
                    if isActiveNow {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(manager.selectedColor.displayColor.opacity(0.2))
                            .foregroundColor(manager.selectedColor.displayColor)
                            .cornerRadius(4)
                    }
                }

                Text(agent.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Cursor hook action button
            if agent.isHookConfigurable {
                Button(action: {
                    if manager.cursorHooksInstalled {
                        _ = manager.removeCursorHooks()
                        manager.hookAlertMessage = "Cursor hooks removed."
                    } else {
                        _ = manager.installCursorHooks()
                        manager.hookAlertMessage = "Cursor hooks installed! Restart Cursor to apply."
                    }
                    manager.showingHookAlert = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: manager.cursorHooksInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                        Text(manager.cursorHooksInstalled ? "Hooks Active" : "Setup Hooks")
                    }
                    .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(manager.cursorHooksInstalled ? .green : .blue)
                .help(manager.cursorHooksInstalled ? "Click to uninstall hooks" : "Click to auto-install Cursor hooks into ~/.cursor/hooks.json")
            }

            // Toggle
            Toggle("", isOn: Binding(
                get: { agent.isEnabled },
                set: { _ in manager.toggleAgent(agent.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActiveNow ? manager.selectedColor.displayColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActiveNow ? manager.selectedColor.displayColor.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var isActiveNow: Bool {
        guard manager.isMasterEnabled && manager.isPulsing else { return false }
        if let activeId = manager.activeAgentId {
            return activeId == agent.name || activeId.contains(agent.name)
        }
        return false
    }
}
