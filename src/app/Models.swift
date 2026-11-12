import Foundation
import SwiftUI

public enum PulseColor: String, CaseIterable, Codable, Identifiable {
    case amber = "Amber"
    case green = "Green"

    public var id: String { rawValue }

    public var smcValue: Int {
        switch self {
        case .amber: return 4
        case .green: return 3
        }
    }

    public var displayColor: Color {
        switch self {
        case .amber:
            return Color(red: 1.0, green: 0.62, blue: 0.1)
        case .green:
            return Color(red: 0.2, green: 0.88, blue: 0.35)
        }
    }

    public var glowColor: Color {
        switch self {
        case .amber:
            return Color(red: 1.0, green: 0.55, blue: 0.0, opacity: 0.7)
        case .green:
            return Color(red: 0.15, green: 0.95, blue: 0.35, opacity: 0.7)
        }
    }
}

public struct MonitoredAgent: Identifiable, Codable, Equatable {
    public var id: String
    public var name: String
    public var iconName: String
    public var detail: String
    public var processNames: [String]
    public var hookPath: String?
    public var isHookConfigurable: Bool
    public var isEnabled: Bool
    public var isCustom: Bool

    public static let defaults: [MonitoredAgent] = [
        MonitoredAgent(
            id: "cursor",
            name: "Cursor Agent",
            iconName: "cursorarrow.rays",
            detail: "Cursor IDE AI Agent (Hooks & Process)",
            processNames: ["Cursor", "cursor", "Cursor Helper"],
            hookPath: "~/.cursor/hooks.json",
            isHookConfigurable: true,
            isEnabled: true,
            isCustom: false
        ),
        MonitoredAgent(
            id: "claude",
            name: "Claude Code",
            iconName: "terminal.fill",
            detail: "Anthropic Claude Code CLI Assistant",
            processNames: ["claude"],
            hookPath: nil,
            isHookConfigurable: false,
            isEnabled: true,
            isCustom: false
        ),
        MonitoredAgent(
            id: "windsurf",
            name: "Windsurf",
            iconName: "wind",
            detail: "Codeium Windsurf IDE AI Cascade",
            processNames: ["Windsurf", "windsurf"],
            hookPath: nil,
            isHookConfigurable: false,
            isEnabled: true,
            isCustom: false
        ),
        MonitoredAgent(
            id: "aider",
            name: "Aider",
            iconName: "hammer.fill",
            detail: "Aider AI Pair Programming CLI",
            processNames: ["aider"],
            hookPath: nil,
            isHookConfigurable: false,
            isEnabled: true,
            isCustom: false
        ),
        MonitoredAgent(
            id: "antigravity",
            name: "Antigravity",
            iconName: "sparkles",
            detail: "Google Antigravity Coding Agent",
            processNames: ["agy", "antigravity"],
            hookPath: nil,
            isHookConfigurable: false,
            isEnabled: true,
            isCustom: false
        ),
        MonitoredAgent(
            id: "copilot",
            name: "VS Code / Copilot",
            iconName: "chevron.left.forwardslash.chevron.right",
            detail: "VS Code Copilot / Chat Agent",
            processNames: ["Code", "code"],
            hookPath: nil,
            isHookConfigurable: false,
            isEnabled: false,
            isCustom: false
        )
    ]
}

