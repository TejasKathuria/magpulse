import Foundation
import Combine
import SwiftUI
import AppKit
import Darwin

public class MagpulseManager: ObservableObject {
    public static let shared = MagpulseManager()

    // Configuration Paths
    public let confPath = "/tmp/magpulse.conf"
    public let activeFlagPath = "/tmp/magpulse.active"
    public let cursorFlagPath = "/tmp/cursor-led.active"
    public let helperPath = "/usr/local/bin/magpulse-daemon"
    public let sudoersPath = "/etc/sudoers.d/magpulse"

    // Published State
    @Published public var isMasterEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isMasterEnabled, forKey: "isMasterEnabled")
            syncConfigAsync()
            if !isMasterEnabled {
                stopPulsing()
            }
        }
    }

    @Published public var pulseSpeed: Double {
        didSet {
            UserDefaults.standard.set(pulseSpeed, forKey: "pulseSpeed")
            syncConfigAsync()
        }
    }

    @Published public var selectedColor: PulseColor {
        didSet {
            UserDefaults.standard.set(selectedColor.rawValue, forKey: "selectedColor")
            syncConfigAsync()
        }
    }

    @Published public var agents: [MonitoredAgent] {
        didSet {
            saveAgents()
        }
    }

    @Published public var isHelperInstalled: Bool = false
    @Published public var isPulsing: Bool = false
    @Published public var activeAgentId: String? = nil
    @Published public var isTesting: Bool = false
    @Published public var cursorHooksInstalled: Bool = false
    @Published public var statusMessage: String = "Ready"

    // UI Dialog & Alert State
    @Published public var showingCustomAgentSheet: Bool = false
    @Published public var newAgentName: String = ""
    @Published public var newAgentProcess: String = ""
    @Published public var showingHelperAlert: Bool = false
    @Published public var helperAlertMessage: String = ""
    @Published public var showingHookAlert: Bool = false
    @Published public var hookAlertMessage: String = ""

    // Background work queue
    private let monitorQueue = DispatchQueue(label: "com.magpulse.monitor", qos: .utility)
    private var monitorSource: DispatchSourceTimer?
    private var testTimer: Timer?

    public init() {
        self.isMasterEnabled = UserDefaults.standard.object(forKey: "isMasterEnabled") as? Bool ?? true
        self.pulseSpeed = UserDefaults.standard.object(forKey: "pulseSpeed") as? Double ?? 2.4
        let colorString = UserDefaults.standard.string(forKey: "selectedColor") ?? PulseColor.amber.rawValue
        self.selectedColor = PulseColor(rawValue: colorString) ?? .amber

        if let data = UserDefaults.standard.data(forKey: "monitoredAgents"),
           let decoded = try? JSONDecoder().decode([MonitoredAgent].self, from: data) {
            self.agents = decoded
        } else {
            self.agents = MonitoredAgent.defaults
        }

        // Defer background checks so UI appears instantly without lag
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.syncConfigAsync()
            self?.startBackgroundMonitoring()
        }
    }

    deinit {
        monitorSource?.cancel()
        testTimer?.invalidate()
    }

    // MARK: - Background Monitoring Loop

    public func startBackgroundMonitoring() {
        monitorSource?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(750))
        timer.setEventHandler { [weak self] in
            self?.performBackgroundCheck()
        }
        timer.resume()
        monitorSource = timer
    }

    private func performBackgroundCheck() {
        // 1. Check helper & hook status on disk
        let daemonExists = FileManager.default.fileExists(atPath: helperPath)
        let aclcExists = FileManager.default.fileExists(atPath: "/usr/local/bin/aclc")
        let sudoersExists = FileManager.default.fileExists(atPath: sudoersPath) ||
                            FileManager.default.fileExists(atPath: "/etc/sudoers.d/aclc")
        let helperOk = (daemonExists || aclcExists) && sudoersExists

        let home = NSHomeDirectory()
        let hooksPath = "\(home)/.cursor/hooks.json"
        let startScript = "\(home)/.cursor/hooks/led-start.sh"
        let stopScript = "\(home)/.cursor/hooks/led-stop.sh"
        let hasScripts = FileManager.default.fileExists(atPath: startScript) &&
                         FileManager.default.fileExists(atPath: stopScript)

        var hasConfig = false
        if let data = try? Data(contentsOf: URL(fileURLWithPath: hooksPath)),
           let str = String(data: data, encoding: .utf8) {
            hasConfig = str.contains("led-start.sh")
        }
        let hooksOk = hasScripts && hasConfig

        // 2. Check flags and running processes
        let cursorFlag = FileManager.default.fileExists(atPath: cursorFlagPath)
        let magpulseFlag = FileManager.default.fileExists(atPath: activeFlagPath)

        // Query running processes using fast Darwin kernel proc_listpids
        let runningProcessNames = getRunningProcessNames()
        let isDaemonRunning = runningProcessNames.contains("magpulse-daemon")

        // Identify detected agent
        var detected: String? = nil
        let currentAgents = self.agents
        let enabled = self.isMasterEnabled
        let testing = self.isTesting

        if enabled && !testing {
            if cursorFlag || magpulseFlag {
                if let cursorAgent = currentAgents.first(where: { $0.id == "cursor" && $0.isEnabled }) {
                    detected = cursorAgent.name
                } else {
                    detected = "Hook Signal"
                }
            }

            if detected == nil {
                for agent in currentAgents where agent.isEnabled {
                    let matches = agent.processNames.contains { pName in
                        runningProcessNames.contains(pName.lowercased())
                    }
                    if matches {
                        detected = agent.name
                        break
                    }
                }
            }
        }

        // 3. Dispatch UI state updates to Main Thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.isHelperInstalled != helperOk {
                self.isHelperInstalled = helperOk
            }
            if self.cursorHooksInstalled != hooksOk {
                self.cursorHooksInstalled = hooksOk
            }

            if self.isTesting { return }

            if let agentName = detected {
                self.activeAgentId = agentName
                if !self.isPulsing {
                    self.isPulsing = true
                    self.statusMessage = "Pulsing for \(agentName)"
                    self.createActiveFlagAsync()
                }
            } else {
                self.activeAgentId = nil
                if self.isPulsing {
                    self.isPulsing = false
                    self.statusMessage = self.isMasterEnabled ? "Idle - Monitoring agents" : "Disabled"
                    self.removeActiveFlagAsync()
                }
            }
        }

        // Ensure daemon is started if helper is installed and daemon isn't running
        if helperOk && !isDaemonRunning && enabled {
            spawnDaemonProcessAsync()
        }
    }

    // Fast, in-memory Darwin kernel process scanner (takes < 2ms, zero subprocesses)
    private func getRunningProcessNames() -> Set<String> {
        var pids = [pid_t](repeating: 0, count: 2048)
        let bytesReturned = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        let count = Int(bytesReturned) / MemoryLayout<pid_t>.stride
        var names = Set<String>()
        names.reserveCapacity(count)

        var nameBuffer = [CChar](repeating: 0, count: 1024)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let len = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            if len > 0 {
                let name = String(cString: nameBuffer)
                names.insert(name.lowercased())
            }
        }
        return names
    }

    // MARK: - Pulsing Control

    public func startPulsing(reason: String = "Active") {
        isPulsing = true
        statusMessage = "Pulsing for \(reason)"
        createActiveFlagAsync()
    }

    public func stopPulsing() {
        isPulsing = false
        statusMessage = isMasterEnabled ? "Idle - Monitoring agents" : "Disabled"
        removeActiveFlagAsync()
    }

    public func triggerTestPulse(duration: Double = 5.0) {
        guard !isTesting else { return }
        isTesting = true
        statusMessage = "Testing MagSafe LED (\(Int(duration))s)..."
        createActiveFlagAsync()

        testTimer?.invalidate()
        testTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.isTesting = false
            self?.stopPulsing()
        }
    }

    private func createActiveFlagAsync() {
        let flag = activeFlagPath
        monitorQueue.async { [weak self] in
            try? "1".write(toFile: flag, atomically: true, encoding: .utf8)
            self?.syncConfigFile()
        }
    }

    private func removeActiveFlagAsync() {
        let flag1 = activeFlagPath
        let flag2 = cursorFlagPath
        monitorQueue.async { [weak self] in
            try? FileManager.default.removeItem(atPath: flag1)
            try? FileManager.default.removeItem(atPath: flag2)
            self?.syncConfigFile()
            self?.resetSMCAsync()
        }
    }

    // MARK: - Config File Sync

    public func syncConfigAsync() {
        monitorQueue.async { [weak self] in
            self?.syncConfigFile()
        }
    }

    private func syncConfigFile() {
        let activeVal = (isMasterEnabled && (isPulsing || isTesting)) ? 1 : 0
        let confContent = """
        active=\(activeVal)
        color=\(selectedColor == .green ? "green" : "amber")
        period=\(String(format: "%.2f", pulseSpeed))
        pwm=12000
        flagfile=\(activeFlagPath)
        """
        try? confContent.write(toFile: confPath, atomically: true, encoding: .utf8)
    }

    private func spawnDaemonProcessAsync() {
        let bin = helperPath
        guard FileManager.default.fileExists(atPath: bin) else { return }

        monitorQueue.async {
            let proc = Process()
            proc.launchPath = "/bin/sh"
            proc.arguments = ["-c", "pgrep -x magpulse-daemon >/dev/null || (nohup sudo -n \(bin) daemon >/dev/null 2>&1 &)"]
            try? proc.run()
        }
    }

    private func resetSMCAsync() {
        let bin = helperPath
        let aclcBin = "/usr/local/bin/aclc"
        monitorQueue.async {
            let proc = Process()
            proc.launchPath = "/bin/sh"
            let target = FileManager.default.fileExists(atPath: aclcBin) ? aclcBin : bin
            proc.arguments = ["-c", "sudo -n \(target) 0 2>/dev/null || true"]
            try? proc.run()
        }
    }

    // MARK: - Helper Setup & Status

    public func installHelper(completion: @escaping (Bool, String?) -> Void) {
        let appBundlePath = Bundle.main.bundlePath
        let projectBin = (appBundlePath as NSString).deletingLastPathComponent + "/magpulse-daemon"
        let sourceBin = Bundle.main.path(forResource: "magpulse-daemon", ofType: nil) ??
                        (FileManager.default.fileExists(atPath: projectBin) ? projectBin : "./magpulse-daemon")

        let user = NSUserName()
        let appleScriptCode = """
        do shell script "mkdir -p /usr/local/bin && cp -f '\(sourceBin)' /usr/local/bin/magpulse-daemon && chmod 755 /usr/local/bin/magpulse-daemon && ln -sf /usr/local/bin/magpulse-daemon /usr/local/bin/aclc && ln -sf /usr/local/bin/magpulse-daemon /usr/local/bin/aclc-pulse && echo '\(user) ALL=(root) NOPASSWD: /usr/local/bin/magpulse-daemon, /usr/local/bin/aclc, /usr/local/bin/aclc-pulse' > /etc/sudoers.d/magpulse && chmod 440 /etc/sudoers.d/magpulse" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var errorInfo: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScriptCode) {
                scriptObject.executeAndReturnError(&errorInfo)
                DispatchQueue.main.async {
                    if let err = errorInfo {
                        let errMsg = err[NSAppleScript.errorMessage] as? String ?? "Authorization cancelled or failed"
                        completion(false, errMsg)
                    } else {
                        self?.isHelperInstalled = true
                        self?.spawnDaemonProcessAsync()
                        completion(true, nil)
                    }
                }
            } else {
                DispatchQueue.main.async { completion(false, "Could not initialize AppleScript") }
            }
        }
    }

    public func uninstallHelper(completion: @escaping (Bool) -> Void) {
        let appleScriptCode = """
        do shell script "rm -f /usr/local/bin/magpulse-daemon /usr/local/bin/aclc /usr/local/bin/aclc-pulse /etc/sudoers.d/magpulse && pkill -x magpulse-daemon 2>/dev/null || true" with administrator privileges
        """
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var errorInfo: NSDictionary?
            if let scriptObject = NSAppleScript(source: appleScriptCode) {
                scriptObject.executeAndReturnError(&errorInfo)
                DispatchQueue.main.async {
                    self?.isHelperInstalled = false
                    completion(errorInfo == nil)
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Cursor Hooks Management

    public func installCursorHooks() -> Bool {
        let home = NSHomeDirectory()
        let hooksDir = "\(home)/.cursor/hooks"
        let hooksJsonPath = "\(home)/.cursor/hooks.json"

        do {
            try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

            let startScript = """
            #!/bin/bash
            cat >/dev/null
            touch /tmp/cursor-led.active
            touch /tmp/magpulse.active
            pgrep -x magpulse-daemon >/dev/null || (nohup sudo -n /usr/local/bin/magpulse-daemon daemon >/dev/null 2>&1 &)
            echo '{"continue": true}'
            """

            let stopScript = """
            #!/bin/bash
            cat >/dev/null
            rm -f /tmp/cursor-led.active /tmp/magpulse.active
            sleep 0.3
            sudo -n /usr/local/bin/aclc 0 2>/dev/null || sudo -n /usr/local/bin/magpulse-daemon set 0 2>/dev/null || true
            echo '{}'
            """

            try startScript.write(toFile: "\(hooksDir)/led-start.sh", atomically: true, encoding: .utf8)
            try stopScript.write(toFile: "\(hooksDir)/led-stop.sh", atomically: true, encoding: .utf8)

            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(hooksDir)/led-start.sh")
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(hooksDir)/led-stop.sh")

            let hookConfig = """
            {
              "version": 1,
              "hooks": {
                "beforeSubmitPrompt": [{ "command": "./hooks/led-start.sh" }],
                "stop": [{ "command": "./hooks/led-stop.sh" }]
              }
            }
            """
            try hookConfig.write(toFile: hooksJsonPath, atomically: true, encoding: .utf8)

            DispatchQueue.main.async { self.cursorHooksInstalled = true }
            return true
        } catch {
            return false
        }
    }

    public func removeCursorHooks() -> Bool {
        let home = NSHomeDirectory()
        let startScript = "\(home)/.cursor/hooks/led-start.sh"
        let stopScript = "\(home)/.cursor/hooks/led-stop.sh"
        try? FileManager.default.removeItem(atPath: startScript)
        try? FileManager.default.removeItem(atPath: stopScript)
        DispatchQueue.main.async { self.cursorHooksInstalled = false }
        return true
    }

    // MARK: - Agent Management

    public func toggleAgent(_ agentId: String) {
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].isEnabled.toggle()
        }
    }

    public func addCustomAgent(name: String, processName: String) {
        let newAgent = MonitoredAgent(
            id: UUID().uuidString,
            name: name,
            iconName: "gearshape.fill",
            detail: "Custom agent (\(processName))",
            processNames: [processName],
            hookPath: nil,
            isHookConfigurable: false,
            isEnabled: true,
            isCustom: true
        )
        agents.append(newAgent)
    }

    public func removeAgent(at indexSet: IndexSet) {
        agents.remove(atOffsets: indexSet)
    }

    private func saveAgents() {
        if let encoded = try? JSONEncoder().encode(agents) {
            UserDefaults.standard.set(encoded, forKey: "monitoredAgents")
        }
    }
}
