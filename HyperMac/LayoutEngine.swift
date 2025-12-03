//
//  LayoutEngine.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL GOLD: Master-Stack + Safety + Zombie Memory (Fixes Reordering)
//

import Cocoa
import ApplicationServices

class LayoutEngine {

    static let shared = LayoutEngine()
    private var windows: [ManagedWindow] = []
    
    // CACHE: Prevents CPU usage when windows aren't moving
    private var lastTargetFrames: [CGWindowID: CGRect] = [:]
    
    // 🔥 ZOMBIE MEMORY: Tracks windows that "blink" out of existence temporarily
    // This fixes the issue where windows swap places when switching desktops.
    private var missingWindows: [CGWindowID: Date] = [:]
    
    // CONFIGURATION
    private let gap: CGFloat = 12.0
    private let genericMinW: CGFloat = 400.0
    
    // CONSTRAINTS
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

    // 1. UPDATE WINDOWS (With Zombie Logic)
    func updateWindows(_ newWindows: [ManagedWindow]) {
        let now = Date()
        
        var updatedList: [ManagedWindow] = []
        
        // A. Process Existing Windows (Maintain Order)
        for existing in self.windows {
            if let match = newWindows.first(where: { $0.windowID == existing.windowID }) {
                // Window Found: Update data and remove from missing list
                updatedList.append(match)
                missingWindows.removeValue(forKey: existing.windowID)
            } else {
                // Window Missing: Check Zombie Status
                // If gone for less than 2.0 seconds, keep it in memory (it might be blinking)
                let missingSince = missingWindows[existing.windowID] ?? now
                missingWindows[existing.windowID] = missingSince
                
                if now.timeIntervalSince(missingSince) < 2.0 {
                    // Keep the ghost in the list so the index doesn't shift
                    updatedList.append(existing)
                } else {
                    // Gone too long, delete it
                    missingWindows.removeValue(forKey: existing.windowID)
                }
            }
        }
        
        // B. Process Brand New Windows
        for newWin in newWindows {
            if !updatedList.contains(where: { $0.windowID == newWin.windowID }) {
                updatedList.append(newWin)
            }
        }
        
        self.windows = updatedList
    }
    
    // 2. RESET CACHE (Called by SpaceManager)
    func resetCache() {
        lastTargetFrames.removeAll()
    }
    
    // 3. MANUAL SWAPPING
    func moveFocusedWindow(_ direction: WindowAction) {
        guard let focused = WindowDiscovery.shared.getFocusedWindow() else { return }
        guard let currentIndex = windows.firstIndex(where: { $0.windowID == focused.windowID }) else { return }
        
        var newIndex = currentIndex
        switch direction {
        case .moveLeft:  newIndex = 0 // Promote to Master
        case .moveRight: newIndex = 1 // Demote to Stack
        case .moveUp:    newIndex = currentIndex - 1
        case .moveDown:  newIndex = currentIndex + 1
        default: return
        }
        
        if newIndex < 0 { newIndex = 0 }
        if newIndex >= windows.count { newIndex = windows.count - 1 }
        
        if newIndex != currentIndex {
            print("🔀 Swapping [\(currentIndex)] -> [\(newIndex)]")
            windows.swapAt(currentIndex, newIndex)
            applyLayout()
        }
    }

    // 4. APPLY LAYOUT
    func applyLayout() {
        // Stop if dragging
        if SpaceManager.shared.isThrowing { return }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let vf = screen.visibleFrame.insetBy(dx: gap, dy: gap)

            // 🔥 FILTER ZOMBIES:
            // We only tile windows that are ACTUALLY on screen right now.
            // We kept the zombies in the 'windows' array to preserve order,
            // but we filter them out here so we don't try to move a ghost.
            let group = windows.filter { win in
                if missingWindows[win.windowID] != nil { return false }
                return win.isOnScreen
            }
            
            if group.isEmpty { continue }
            
            let rects = calculateMasterStackRects(bounds: vf, windows: group)
            
            for (i, win) in group.enumerated() {
                guard let ax = win.axElement else { continue }
                if i < rects.count {
                    let newTarget = rects[i]
                    let winID = win.windowID
                    
                    if let lastTarget = lastTargetFrames[winID] {
                        if abs(lastTarget.minX - newTarget.minX) < 1.0 &&
                           abs(lastTarget.minY - newTarget.minY) < 1.0 &&
                           abs(lastTarget.width - newTarget.width) < 1.0 &&
                           abs(lastTarget.height - newTarget.height) < 1.0 {
                            continue
                        }
                    }
                    
                    lastTargetFrames[winID] = newTarget
                    WindowAnimator.shared.animate(window: ax, to: newTarget)
                }
            }
        }
    }
    
    // 5. ALGORITHM: Master-Stack + Safety
    private func calculateMasterStackRects(bounds: CGRect, windows: [ManagedWindow]) -> [CGRect] {
        if windows.isEmpty { return [] }
        if windows.count == 1 { return [bounds] }
        
        var rects: [CGRect] = []
        
        // Master
        let masterApp = windows[0]
        let desiredWidth = appMinSizes[masterApp.ownerName] ?? genericMinW
        
        var masterWidth = bounds.width / 2.0
        if masterWidth < desiredWidth { masterWidth = desiredWidth }
        
        // Safety Valve
        let minStackWidth: CGFloat = 400.0
        let maxMasterWidth = bounds.width - minStackWidth - gap
        if masterWidth > maxMasterWidth { masterWidth = maxMasterWidth }
        
        let masterRect = CGRect(x: bounds.minX, y: bounds.minY, width: masterWidth, height: bounds.height)
        rects.append(masterRect)
        
        // Stack
        let stackX = bounds.minX + masterWidth + gap
        let stackWidth = bounds.width - masterWidth - gap
        let stackCount = CGFloat(windows.count - 1)
        
        if stackCount <= 0 { return rects }
        
        let stackHeight = (bounds.height - (gap * (stackCount - 1))) / stackCount
        
        for i in 0..<Int(stackCount) {
            let yPos = bounds.minY + (CGFloat(i) * (stackHeight + gap))
            let stackRect = CGRect(x: stackX, y: yPos, width: stackWidth, height: stackHeight)
            rects.append(stackRect)
        }
        
        return rects
    }
}
