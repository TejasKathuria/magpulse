import SwiftUI

public struct ContentView: View {
    @ObservedObject var manager = MagpulseManager.shared

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Header Bar (Text only, no icon square, no subtitle)
                headerSection

                // Helper Permission Banner (if not installed)
                if !manager.isHelperInstalled {
                    helperBanner
                }

                // Status & Test Row (no connector mockup)
                statusBarSection

                // Color & Speed Controls
                VStack(spacing: 16) {
                    colorSelectionSection
                    Divider()
                    speedAdjustmentSection
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Monitored Agents Section
                monitoredAgentsSection

                // Footer / Info
                footerSection
            }
            .padding(20)
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 520, idealHeight: 580)
        .sheet(isPresented: $manager.showingCustomAgentSheet) {
            customAgentSheet
        }
        .alert(isPresented: $manager.showingHelperAlert) {
            Alert(title: Text("SMC Helper Setup"), message: Text(manager.helperAlertMessage), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Magpulse")
                .font(.system(size: 22, weight: .bold))

            Spacer()

            // Enable / Disable Master Toggle
            HStack(spacing: 8) {
                Text(manager.isMasterEnabled ? "Enabled" : "Disabled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(manager.isMasterEnabled ? manager.selectedColor.displayColor : .secondary)

                Toggle("", isOn: $manager.isMasterEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(manager.isMasterEnabled ? manager.selectedColor.displayColor.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Status & Test Section

    private var statusBarSection: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(manager.isMasterEnabled && (manager.isPulsing || manager.isTesting) ? manager.selectedColor.displayColor : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)

                Text(statusLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                manager.triggerTestPulse(duration: 5.0)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: manager.isTesting ? "waveform" : "bolt.fill")
                    Text(manager.isTesting ? "Testing (5s)..." : "Test MagSafe LED")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.selectedColor.displayColor)
            .disabled(!manager.isMasterEnabled || manager.isTesting)
        }
        .padding(.horizontal, 4)
    }

    private var statusLabel: String {
        if !manager.isMasterEnabled {
            return "Magpulse Disabled"
        }
        if manager.isTesting {
            return "Testing MagSafe LED..."
        }
        if manager.isPulsing {
            if let agent = manager.activeAgentId {
                return "Pulsing for \(agent)"
            }
            return "Pulsing MagSafe LED"
        }
        return "Idle (Monitoring agents)"
    }

    // MARK: - Helper Setup Banner

    private var helperBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("SMC Hardware Access Required")
                    .font(.system(size: 12, weight: .bold))
                Text("MagSafe LED requires root SMC privileges to communicate with AppleSMC.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                manager.installHelper { success, error in
                    if success {
                        manager.helperAlertMessage = "Helper installed successfully! Magpulse is ready."
                    } else {
                        manager.helperAlertMessage = "Helper installation failed: \(error ?? "Unknown error")"
                    }
                    manager.showingHelperAlert = true
                }
            }) {
                Text("1-Click Setup")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Color Selection

    private var colorSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LED Pulse Color")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(manager.selectedColor.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(manager.selectedColor.displayColor)
            }

            HStack(spacing: 12) {
                // Amber Option
                colorOptionCard(
                    color: .amber,
                    title: "Amber / Orange",
                    subtitle: "Classic charging glow",
                    iconColor: Color(red: 1.0, green: 0.62, blue: 0.1)
                )

                // Green Option
                colorOptionCard(
                    color: .green,
                    title: "Green",
                    subtitle: "Fully charged glow",
                    iconColor: Color(red: 0.2, green: 0.88, blue: 0.35)
                )
            }
        }
    }

    private func colorOptionCard(color: PulseColor, title: String, subtitle: String, iconColor: Color) -> some View {
        let isSelected = manager.selectedColor == color

        return Button(action: {
            manager.selectedColor = color
        }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconColor)
                        .frame(width: 22, height: 22)
                        .shadow(color: iconColor.opacity(isSelected ? 0.7 : 0.2), radius: isSelected ? 6 : 2)

                    if isSelected {
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 18, height: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .primary : .secondary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(iconColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? iconColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? iconColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed Adjustment

    private var speedAdjustmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pulse Breathing Speed")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(String(format: "%.1f", manager.pulseSpeed)) s / breath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(manager.selectedColor.displayColor)
            }

            // Slider
            HStack(spacing: 12) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Slider(value: $manager.pulseSpeed, in: 0.8...5.0, step: 0.1)
                    .accentColor(manager.selectedColor.displayColor)

                Image(systemName: "tortoise.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Preset Buttons
            HStack(spacing: 8) {
                speedPresetButton(title: "Fast (1.2s)", value: 1.2)
                speedPresetButton(title: "Normal (2.4s)", value: 2.4)
                speedPresetButton(title: "Relaxed (3.6s)", value: 3.6)
            }
        }
    }

    private func speedPresetButton(title: String, value: Double) -> some View {
        let isCurrent = abs(manager.pulseSpeed - value) < 0.15

        return Button(action: {
            manager.pulseSpeed = value
        }) {
            Text(title)
                .font(.system(size: 11, weight: isCurrent ? .bold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isCurrent ? manager.selectedColor.displayColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(isCurrent ? manager.selectedColor.displayColor : .secondary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? manager.selectedColor.displayColor : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Monitored Agents

    private var monitoredAgentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monitored AI Agents")
                        .font(.system(size: 14, weight: .bold))
                    Text("Magpulse breathes whenever these agents are running or processing prompts.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    manager.showingCustomAgentSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Custom")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            // Agent Rows
            VStack(spacing: 8) {
                ForEach(manager.agents) { agent in
                    AgentRowView(manager: manager, agent: agent)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: manager.isHelperInstalled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(manager.isHelperInstalled ? .green : .orange)
                    .font(.system(size: 12))

                Text(manager.isHelperInstalled ? "SMC Helper Active" : "Helper Uninstalled")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if manager.isHelperInstalled {
                Button(action: {
                    manager.uninstallHelper { _ in }
                }) {
                    Text("Uninstall Helper")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Custom Agent Sheet

    private var customAgentSheet: some View {
        VStack(spacing: 16) {
            Text("Add Custom Agent")
                .font(.system(size: 16, weight: .bold))

            Text("Enter the display name and UNIX process name (e.g. ollama, python, node) to monitor.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Agent Display Name")
                    .font(.system(size: 11, weight: .semibold))
                TextField("e.g. Local LLM / Ollama", text: $manager.newAgentName)
                    .textFieldStyle(.roundedBorder)

                Text("Process Name")
                    .font(.system(size: 11, weight: .semibold))
                TextField("e.g. ollama", text: $manager.newAgentProcess)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.vertical, 8)

            HStack {
                Button("Cancel") {
                    manager.showingCustomAgentSheet = false
                    manager.newAgentName = ""
                    manager.newAgentProcess = ""
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Add Agent") {
                    if !manager.newAgentName.isEmpty && !manager.newAgentProcess.isEmpty {
                        manager.addCustomAgent(name: manager.newAgentName, processName: manager.newAgentProcess)
                        manager.showingCustomAgentSheet = false
                        manager.newAgentName = ""
                        manager.newAgentProcess = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.newAgentName.isEmpty || manager.newAgentProcess.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
