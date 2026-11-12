# ⚡️ Magpulse

> **Breathing MagSafe LED indicator for AI Agents on Apple Silicon MacBooks.**

**Magpulse** is a native macOS application that turns your MacBook's MagSafe 3 charging LED into a dynamic breathing/pulsing status light whenever your AI coding agents are working.

---

## ✨ Features

1. **🔘 Enable / Disable Master Toggle**
   - Instantly activate or silence Magpulse with a single switch.
   - When disabled, your MagSafe LED immediately returns to standard macOS charging behavior.
   - Accessible both from the main window and the macOS Menu Bar.

2. **🤖 Monitored Agent Selection**
   - Choose which AI agents trigger the breathing animation:
     - **Cursor**: Full hook support (`beforeSubmitPrompt` / `stop`) + process monitoring.
     - **Claude Code**: Terminal AI agent monitoring (`claude`).
     - **Windsurf**: Cascade AI agent monitoring (`windsurf`).
     - **Aider**: AI pair-programmer CLI (`aider`).
     - **Antigravity**: Google DeepMind coding agent (`agy`).
     - **VS Code / Copilot**: Coding assistant monitoring (`code`).
     - **Custom Agents**: Add any UNIX process name (e.g. `ollama`, `python`, `node`) or custom flag file.
   - Live activity badges indicate which agent is actively pulsing.
   - One-click **"Setup Hooks"** button for Cursor IDE auto-configuration.

3. **⏱️ Speed Adjustment**
   - Real-time breathing period slider from **0.8s** (fast pulse) to **5.0s** (relaxed pulse).
   - Quick one-click presets:
     - ⚡ **Fast (1.2s)**
     - 💨 **Normal (2.4s)**
     - 🧘 **Relaxed (3.6s)**
   - Speed adjusts in real-time on your MagSafe plug while pulsing.

4. **🎨 Amber or Green Color Selection**
   - **Amber / Orange (SMC 4)**: The classic warm charging glow.
   - **Green (SMC 3)**: The crisp fully charged glow.

5. **⚡️ Hardware Test & Status**
   - Live status indicator displaying current monitoring activity.
   - **"Test MagSafe LED"** button: Pulses your hardware LED for 5 seconds to verify compatibility immediately.

6. **🛡️ Simple 1-Click Privileged Helper Setup**
   - Communicating with AppleSMC (`ACLC` key) requires root privileges.
   - Magpulse provides a **1-Click Setup** button inside the app that configures passwordless sudo for only the lightweight Magpulse daemon via `/etc/sudoers.d/magpulse`.
   - Clean uninstaller included.

---

## 💻 Hardware Requirements

- **MacBook Pro** (14" or 16", 2021 or later with M1 Pro/Max, M2, M3, M4)
- **MacBook Air** (13" or 15", 2022 or later with M2, M3, M4)
- Connected MagSafe 3 cable.

---

## 🚀 Getting Started

### Option 1: Open the App

You can open the built app directly:
```bash
open Magpulse.app
```
Or drag `Magpulse.app` into your `/Applications` folder!

### Option 2: 1-Click Setup Inside the App

1. Launch **Magpulse.app**.
2. Click **"1-Click Setup"** on the banner (prompts once for your Mac password / Touch ID to configure SMC privileges).
3. Click **"Test MagSafe LED"** — watch your physical MagSafe plug breathe!
4. For Cursor IDE users: Click **"Setup Hooks"** next to Cursor in the agent list.
5. Select your favorite color (Amber or Green) and breathing speed.

---

## 🛠️ Command Line Tools & Scripts

For advanced users or terminal workflows, standalone CLI utilities are provided:

```bash
# Rebuild the app and C daemons anytime
./scripts/build-app.sh

# Install the SMC helper via terminal
./scripts/install-helper.sh

# Test the pulse via terminal (5s test)
sudo magpulse-daemon test green 2.0

# Manually trigger pulse flag
touch /tmp/magpulse.active

# Stop pulse flag
rm -f /tmp/magpulse.active

# Restore LED to system charging control
sudo aclc 0

# Uninstall the helper and sudoers rule
./scripts/uninstall-helper.sh
```

---

## 🔬 How It Works Under the Hood

Apple Silicon MacBooks control the MagSafe 3 connector LED via the AppleSMC `ACLC` key:
- `0`: System automatic charging control
- `1`: LED Off
- `3`: Green solid
- `4`: Amber / Orange solid
- `6`: Slow orange blink
- `7`: Fast orange blink

The Magpulse background daemon (`magpulse-daemon`) uses high-frequency software Pulse Width Modulation (PWM) with a gamma-corrected cosine curve ($\gamma \approx 2.2$) to produce an organic "breathing" transition between colors and off states, closely emulating Apple's classic breathing sleep indicators.

