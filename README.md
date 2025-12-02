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

## Current State & Lifecycle Management

**HyperMac is currently in early Alpha.**

While the core physics engine is functional, the application lifecycle is currently tied to the development environment.

* **Menu Bar / Dock:** You may see a menu bar icon, but the "Quit" and "Reload" buttons are currently experimental and may not reliably terminate the process.
* **To Start/Restart:** Run the project directly from Xcode using **Cmd + R**.
* **To Quit:** Stop the process in Xcode or press **Ctrl + C** in the debug console.

---

## Compatibility & Limitations

* **Native Apps (Stable):** Applications built specifically for macOS (Xcode, Notes, Safari, Finder, Calendar) have a high guarantee of stability. They respect accessibility APIs correctly and tile perfectly.
* **Electron/Custom Apps (Experimental):** Apps that draw their own windows (VS Code, Brave, Chrome, Discord, Spotify) are currently "Hit or Miss." We are actively working on normalization layers to make them behave like native apps.

### Known Issues

1.  **Ghost Windows & Popups:**
    * HyperMac sometimes attempts to tile transient UI elements that report themselves as windows.
    * *Examples:* The "Profile" dropdown in Chrome/Brave, hover-over tab information cards, or "Find" bars in VS Code might be detected as a new window and force the layout engine to split the screen.

2.  **VS Code & Electron Dragging:**
    * Moving VS Code or Discord between workspaces using the "Throw" command (Option + Shift + Number) is currently unreliable. These apps often do not respond to the standard accessibility drag events, causing them to flicker or stay on the original desktop.

3.  **The "Lone-to-Lone" Transfer:**
    * Moving a browser from a desktop where it is the *only* window to another desktop where it will *also* be the only window can sometimes fail to trigger a re-tile event. The window moves, but may not snap to full-screen immediately due to stale coordinate reporting.

4.  **Secure Input Pause:**
    * By design, window management commands are disabled when a password field is focused (a macOS security requirement).

---

## Key Features

* **Native Swift Performance:** Zero CPU usage when idle. Uses advanced State Diffing to only calculate layout changes when necessary.
* **Smart Master-Stack Layout:** Automatically promotes your main window to the left (Master) and stacks secondary windows on the right.
* **Xcode Safety Valve:** Includes "Look-Ahead Balancing" to prevent heavy apps like Xcode from being squished or pushing other windows off-screen. It guarantees zero overlap.
* **Physics Engine:** Custom EaseOutExpo animation curves running at 60FPS for smooth, jitter-free window movements.
* **Workspace Integration:** Bridges with native macOS Mission Control spaces using AppleScript injection.

---

## Keybinds

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
| **Option + Shift + R** | Reload Layout | Forces a re-calculation of the grid (useful if you resize manually). |
| **Option + Shift + Q** | Quit HyperMac | Closes the window manager (Experimental). |

---

## Roadmap

We have big plans for Beta v1 and beyond:

* [ ] **Visual Borders:** Active window highlighting with customizable colored borders (similar to Hyprland).
* [ ] **Electron Normalization:** A robust filter to ignore tooltips, dropdowns, and hover cards in browsers and VS Code.
* [ ] **Mouse-Follows-Focus:** Option to auto-focus windows when the mouse hovers over them.
* [ ] **Drag-to-Resize:** Ability to resize the Master/Stack split by dragging the gap with the mouse.
* [ ] **Config File:** A `hypermac.conf` file (dotfile) to customize gaps, speed, and keybinds without recompiling.
* [ ] **Window Rules:** Define specific rules per app (e.g., "Always float Calculator", "Always open Spotify on Workspace 4").
* [ ] **Multi-Monitor Support:** Logic to handle moving windows across different physical displays.
* [ ] **Layout Switching:** Keybinds to toggle between Master-Stack, BSP (Binary Space Partitioning), and Monocle (Full Screen) layouts on the fly.

---

## Installation & Setup

Since HyperMac interacts with low-level macOS APIs, it requires specific permissions.

1.  **Build & Run:** Open `HyperMac.xcodeproj` in Xcode.
2.  **Run:** Press `Cmd + R` to build and launch the daemon.
3.  **Grant Permissions:**
    * **Accessibility:** Required to move and resize windows.
    * **Automation (AppleScript):** Required to switch desktops reliably.
    * **Screen Recording:** Required to read window titles for correct identification (we do not record the screen, but Apple groups the permissions together).
4.  **Enable Mission Control Shortcuts:**
    * Go to **System Settings > Keyboard > Keyboard Shortcuts > Mission Control**.
    * Expand the list and **Enable** "Switch to Desktop 1", "Switch to Desktop 2", etc.
    * Ensure they are mapped to `^1`, `^2` (Control+Number).

## License

MIT License. Feel free to fork and modify!
