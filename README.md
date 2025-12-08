<div align="center">
  <img src="logo_white.png" width="150" height="150" alt="HyperMac Logo" />
  <h1>HyperMac (Alpha)</h1>
  <p>
    <b>A native, lightweight Tiling Window Manager for macOS, targeting the fluidity of Hyprland.</b>
  </p>
</div>

---

HyperMac aims to bridge the gap between the fluid, physics-based tiling experience of Linux (specifically Hyprland) and the native macOS environment. While other window managers exist, HyperMac focuses specifically on motion, interpolation, and the "feel" of the window management, replacing rigid snapping with organic movement.

This project was heavily inspired by the work done on **AeroSpace**. Their success solidified the idea that a robust tiling window manager on macOS was possible and served as a major inspiration for this project's existence.

### Developer Note
I am currently the sole developer working on this project, and I am learning Swift side-by-side specifically to build HyperMac. As such, updates may take time, and the codebase is constantly evolving. Contributions, patience, and bug reports are appreciated.

---

## Current State & Limitations

**HyperMac is currently in early Alpha (v0.2).**

While the core physics engine is functional, the application lifecycle is currently tied to the development environment.

* **Lifecycle:** Run the project directly from Xcode (`Cmd + R`). To quit, stop the process in Xcode, press `Ctrl + C` in the debug console or press quit through HyperMac icon in the status bar.
* **Compatibility:**
    * **Native Apps (Stable):** Apps like Xcode, Safari, and Terminal tile perfectly.
    * **Electron Apps (Experimental):** Apps like VS Code, Discord, or Spotify may behave unpredictably. We are actively working on normalization layers to handle their non-standard window behaviors.

---

## Key Features

* **Native Swift Performance:** Zero CPU usage when idle. Uses advanced State Diffing to only calculate layout changes when necessary.
* **Smart Master-Stack Layout:** Automatically promotes your main window to the left (Master) and stacks secondary windows on the right.
* **Long-Term Memory:** Unlike basic tilers, HyperMac remembers the exact order of your windows. If you switch spaces and come back, your windows will be exactly where you left them.
* **Physics Engine:** Custom **Quartic Ease-Out** animation curves running at 60FPS for smooth, jitter-free window movements.
* **60Hz Optimization:** Implements "Active Frame Dropping." If the macOS WindowServer is busy, HyperMac intelligently skips animation frames to prevent UI freeze and input lag.
* **Workspace Integration:** Bridges with native macOS Mission Control spaces using low-level event injection.

---

## Roadmap & Progress

### Alpha Series (0.x)
*Focus: Stability, physics tuning, tiling correctness, and core UX.*

#### ✔️ v0.1–v0.2 Achievements
- [x] ~~Master-Stack Layout Engine
- [x] ~~Zombie Memory Protection (Prevents layout break on Electron flickers)
- [x] ~~Long-Term Window History (Persistent Rank across spaces)
- [x] ~~Thread-Optimized Animator (Off-Main-Thread logic)
- [x] ~~Smart Backpressure (60Hz "Active Frame Dropping")
- [x] ~~Precision Window Throwing (Pixel-perfect grip logic)
- [x] ~~Atomic Updates (Size/Pos synchronization to prevent tearing)
- [x] ~~Burst Scanning (Reliable discovery on space change)
- [x] ~~Idle CPU Guarantee (0–1% usage at rest)
- [x] ~~Menu Bar Controls (Reload, Quit)
- [x] ~~Electron Normalization (Tier 1: Ignore tooltips, popups, hover cards)

#### v0.3-alpha (The Interaction Build)
- [ ] Mouse-Follows-Focus (optional)
- [ ] Drag-to-Resize (adjust Master/Stack ratio interactively)
- [ ] Snap Back Feature (return manually dragged windows to layout)
- [ ] Transient Window Handling (Spotlight, Raycast, Alfred, etc.)
- [ ] Floating Window Guard (auto-ignore dialogs, preferences)
- [ ] Logger Integration (`os_log` instead of `print()`)

---

### Beta Series (1.x)
*Focus: customization, multi-layout tiling, repeatable configs.*

#### v1.0-beta
- [ ] Visual Borders (active window highlighting, color themes)
- [ ] Config File (`config.hypermac`) for layouts, gaps, animations, borders, keybinds
- [ ] Window Rules (regex-based float/assign/ignore)
- [ ] **Layout Switching:** user-selectable tiling modes:
  - [x]**Master-Stack**
  - **BSP (Binary Space Partitioning)**
  - **Monocle (Fullscreen Tiling)**

#### v1.1-beta
- [ ] Multi-Monitor Support (hot-plug detection + recovery)
- [ ] Cross-Display Throwing (send window to another monitor)
- [ ] Per-Monitor Layouts (each display uses its own scheme)
- [ ] Per-Workspace Profiles (workspace-specific templates)

---

### Production (2.x)
*Focus: polish, UI, distribution, ecosystem.*

#### v2.0
- [ ] Full Standalone App (.dmg, signed & notarized)
- [ ] Settings UI (native preferences)
- [ ] Auto-Updater (Sparkle)
- [ ] Plugin Hooks (custom borders, layouts, rules)
- [ ] Telemetry (opt-in crash + debugging info)

#### v2.1
- [ ] iCloud Sync for configs + layouts
- [ ] Preset Library (community layout themes)
- [ ] Rule & Template Exchange (import/export)
- [ ] Profile Switching (IDE Mode, Browser Mode, Media Mode)

---

### Future / Experimental
- [ ] Predictive Tiling (use heuristics to order windows)
- [ ] Gesture-Controlled Layout Switching
- [ ] AI-Assisted Rule Suggestions
- [ ] Layout Plugin Marketplace

---

## ⌨️ Keybinds

HyperMac uses **Option** as the primary modifier to avoid conflicts with system shortcuts.

### Window Management
| Keybind | Action | Description |
| :--- | :--- | :--- |
| **Option + Shift + H** | Promote Left | Moves focused window to the **Master** (Big) slot. |
| **Option + Shift + L** | Demote Right | Moves focused window to the **Stack** (Right column). |
| **Option + Shift + J** | Swap Down | Swaps position with the window below. |
| **Option + Shift + K** | Swap Up | Swaps position with the window above. |

### Workspaces & Spaces
*Requires "Switch to Desktop N" enabled in System Settings.*

| Keybind | Action | Description |
| :--- | :--- | :--- |
| **Option + 1 ... 4** | Go to Space | Instantly switches to Desktop 1, 2, 3, or 4. |
| **Option + Shift + 1 ... 4** | Throw Window | Grabs the active window and carries it to Desktop 1, 2, 3, or 4. |
| **Option + N** | Next Space | Slides to the next desktop (Right). |
| **Option + P** | Prev Space | Slides to the previous desktop (Left). |

### System
| Keybind | Action | Description |
| :--- | :--- | :--- |
| **Option + Shift + R** | Reload Layout | Forces a re-calculation of the grid. |
| **Option + Shift + Q** | Quit HyperMac | Closes the window manager. |

---

## Installation & Setup

Since HyperMac interacts with low-level macOS APIs, it requires specific permissions.

1.  **Build & Run:** Open `HyperMac.xcodeproj` in Xcode.
2.  **Run:** Press `Cmd + R` to build and launch the daemon.
3.  **Grant Permissions:**
    * **Accessibility:** Required to move and resize windows.
    * **Automation (AppleScript):** Required to switch desktops reliably.
    * **Screen Recording:** Required to read window titles (we do not record the screen, but Apple groups the permissions together).
4.  **Enable Mission Control Shortcuts:**
    * Go to **System Settings > Keyboard > Keyboard Shortcuts > Mission Control**.
    * Expand the list and **Enable** "Switch to Desktop 1", "Switch to Desktop 2", etc.
    * Ensure they are mapped to `^1`, `^2` till 4 (Control+Number).

## License

MIT License. Feel free to fork and modify!
