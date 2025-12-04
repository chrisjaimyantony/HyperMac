//
//  LayoutEngine.swift
//  HyperMac
//
//  Core layout controller for HyperMac. Implements the Master-Stack tiling
//  algorithm, handles window order stability across space changes, and
//  coordinates with WindowAnimator to apply animated window positions.
//
//  Responsibilities:
//  - Maintain a stable, ordered list of managed windows
//  - Protect against reordering when spaces change (Zombie Memory System)
//  - Calculate Master-Stack layout rectangles
//  - Avoid unnecessary AX updates via cached target frames
//  - Support window movement commands (manual promotion/demotion)
//  - Provide safety constraints for apps with minimum usable sizes
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import ApplicationServices

class LayoutEngine {

    static let shared = LayoutEngine()

    // Ordered list of currently managed windows.
    private var windows: [ManagedWindow] = []
    
    // Cache of last applied target frames to avoid redundant AX updates.
    private var lastTargetFrames: [CGWindowID: CGRect] = [:]
    
    // Tracks temporarily “missing” windows to prevent reordering when switching desktops.
    private var missingWindows: [CGWindowID: Date] = [:]
    
    // Layout configuration
    private let gap: CGFloat = 12.0
    private let genericMinW: CGFloat = 400.0
    
    // App-specific minimum widths to prevent squashing important UI.
    private let appMinSizes: [String: CGFloat] = [
        "Xcode": 950.0,
        "Music": 600.0,
        "Spotify": 550.0,
        "Discord": 500.0,
        "System Settings": 600.0,
        "Brave Browser": 500.0,
        "Google Chrome": 500.0,
        "WhatsApp": 500.0,
        "Messages": 450.0
    ]

    // MARK: - 1. Update Window List (Zombie Memory Logic)
    //
    // Preserves window order even when windows temporarily disappear
    // during space transitions or Electron rendering quirks.
    //
    func updateWindows(_ newWindows: [ManagedWindow]) {
        let now = Date()
        var updatedList: [ManagedWindow] = []

        // A. Match existing windows to incoming ones, preserving order.
        for existing in windows {
            if let match = newWindows.first(where: { $0.windowID == existing.windowID }) {
                // Window is still alive — update and clear missing flag.
                updatedList.append(match)
                missingWindows.removeValue(forKey: existing.windowID)
            } else {
                // Window missing — possibly a “blink” during space change.
                let missingSince = missingWindows[existing.windowID] ?? now
                missingWindows[existing.windowID] = missingSince

                // Keep as zombie for up to 2 seconds to preserve index.
                if now.timeIntervalSince(missingSince) < 2.0 {
                    updatedList.append(existing)
                } else {
                    // Remove permanently after timeout.
                    missingWindows.removeValue(forKey: existing.windowID)
                }
            }
        }

        // B. Add new windows not found in existing list.
        for newWin in newWindows {
            if !updatedList.contains(where: { $0.windowID == newWin.windowID }) {
                updatedList.append(newWin)
            }
        }

        windows = updatedList
    }
    
    // MARK: - 2. Reset Cache (used by SpaceManager when switching spaces)
    func resetCache() {
        lastTargetFrames.removeAll()
    }
    
    // MARK: - 3. Manual Swapping / Promotions
    //
    // Moves a focused window within the ordered list.
    // This controls Master promotion and Stack ordering.
    //
    func moveFocusedWindow(_ direction: WindowAction) {
        guard let focused = WindowDiscovery.shared.getFocusedWindow() else { return }
        guard let currentIndex = windows.firstIndex(where: { $0.windowID == focused.windowID }) else { return }
        
        var newIndex = currentIndex
        
        switch direction {
        case .moveLeft:  newIndex = 0              // Promote to Master
        case .moveRight: newIndex = 1              // Demote to Stack
        case .moveUp:    newIndex = currentIndex - 1
        case .moveDown:  newIndex = currentIndex + 1
        default: return
        }
        
        newIndex = min(max(newIndex, 0), windows.count - 1)
        
        if newIndex != currentIndex {
            print("Swapping [\(currentIndex)] → [\(newIndex)]")
            windows.swapAt(currentIndex, newIndex)
            applyLayout()
        }
    }

    // MARK: - 4. Apply Layout (Main Execution)
    //
    // Calculates and applies Master-Stack rectangles to windows on each screen.
    //
    func applyLayout() {
        // Avoid layout while a window is being thrown between spaces.
        if SpaceManager.shared.isThrowing { return }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let visible = screen.visibleFrame.insetBy(dx: gap, dy: gap)

            // Filter out zombie placeholders — only tile real windows.
            let activeWindows = windows.filter { win in
                if missingWindows[win.windowID] != nil { return false }
                return win.isOnScreen
            }
            
            if activeWindows.isEmpty { continue }
            
            // Compute layout rectangles.
            let rects = calculateMasterStackRects(bounds: visible, windows: activeWindows)
            
            // Assign each rect to each window.
            for (i, win) in activeWindows.enumerated() {
                guard let ax = win.axElement else { continue }
                let target = rects[i]
                let id = win.windowID
                
                // Skip if target frame hasn't changed significantly.
                if let last = lastTargetFrames[id] {
                    if abs(last.minX - target.minX) < 1.0 &&
                       abs(last.minY - target.minY) < 1.0 &&
                       abs(last.width - target.width) < 1.0 &&
                       abs(last.height - target.height) < 1.0 {
                        continue
                    }
                }

                lastTargetFrames[id] = target
                WindowAnimator.shared.animate(window: ax, to: target)
            }
        }
    }
    
    // MARK: - 5. Master-Stack Rectangle Calculation
    //
    // Master window gets a wide left column.
    // Remaining windows are stacked vertically on the right.
    //
    private func calculateMasterStackRects(bounds: CGRect, windows: [ManagedWindow]) -> [CGRect] {
        if windows.isEmpty { return [] }
        if windows.count == 1 { return [bounds] }
        
        var rects: [CGRect] = []
        
        // MASTER WIDTH CALCULATION
        let masterApp = windows[0]
        let desiredWidth = appMinSizes[masterApp.ownerName] ?? genericMinW
        
        var masterWidth = bounds.width / 2.0
        if masterWidth < desiredWidth {
            masterWidth = desiredWidth
        }
        
        // Prevent master from consuming too much space.
        let minStackWidth: CGFloat = 400.0
        let maxMasterWidth = bounds.width - minStackWidth - gap
        if masterWidth > maxMasterWidth {
            masterWidth = maxMasterWidth
        }
        
        // Master rectangle.
        let masterRect = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: masterWidth,
            height: bounds.height
        )
        rects.append(masterRect)
        
        // STACK WINDOWS
        let stackX = bounds.minX + masterWidth + gap
        let stackWidth = bounds.width - masterWidth - gap
        let stackCount = CGFloat(windows.count - 1)
        
        if stackCount <= 0 { return rects }
        
        let stackHeight = (bounds.height - (gap * (stackCount - 1))) / stackCount
        
        for i in 0..<Int(stackCount) {
            let yPos = bounds.minY + CGFloat(i) * (stackHeight + gap)
            let stackRect = CGRect(x: stackX, y: yPos, width: stackWidth, height: stackHeight)
            rects.append(stackRect)
        }
        
        return rects
    }
}
