//
//  LayoutEngine.swift
//  HyperMac
//
//  Core layout controller for HyperMac.
//  This class implements the Master-Stack tiling algorithm and manages the
//  state of windows across different spaces. It ensures that window order
//  remains stable even when windows are temporarily hidden or moved.
//
//  Responsibilities:
//  - Maintaining a stable, ordered list of managed windows.
//  - Preserving window order (History) across space changes.
//  - Calculating precise layout rectangles for the Master-Stack pattern.
//  - coordinating with the WindowAnimator to apply updates smoothly.
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import ApplicationServices
import CoreGraphics

class LayoutEngine {

    // Singleton instance to ensure only one layout engine manages the state.
    static let shared = LayoutEngine()

    // The current list of windows being managed and tiled.
    private var windows: [ManagedWindow] = []
    
    // Persistent History (Long-Term Memory):
    // This dictionary stores the last known index (rank) of every window ID encountered.
    // It is used to restore the correct order of windows when switching back to a desktop,
    // preventing tiles from swapping positions randomly.
    private var windowOrderHistory: [CGWindowID: Int] = [:]
    
    // Caches the last calculated frame for each window ID.
    // This allows us to skip expensive Accessibility API calls if the window is already in the correct place.
    private var lastTargetFrames: [CGWindowID: CGRect] = [:]
    
    // A timer used to delay layout updates while the user is actively interacting (e.g., resizing).
    private var debounceTimer: DispatchWorkItem?
    
    // Layout Configuration:
    // The visual gap between windows in points.
    private let gap: CGFloat = 12.0
    // The default minimum width for the Master window.
    private let genericMinW: CGFloat = 400.0
    
    // Application-Specific Constraints:
    // A dictionary defining minimum width requirements for specific apps to prevent
    // them from breaking their UI layout when resized too small.
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

    // MARK: - 1. Update Window List
    //
    // This function is called whenever the WindowDiscovery scanner finds a change.
    // It reconciles the new list of windows with the historical order to maintain stability.
    //
    func updateWindows(_ newWindows: [ManagedWindow]) {
        
        // Step 1: Detect New Windows.
        // We compare the IDs currently in memory with the incoming list to see if a brand new app has appeared.
        let oldIDs = Set(windows.map { $0.windowID })
        let incomingIDs = Set(newWindows.map { $0.windowID })
        let hasNewWindow = !incomingIDs.isSubset(of: oldIDs)
        
        // Step 2: Sort by History.
        // Instead of accepting the system's random Z-order, we sort the incoming windows
        // based on the rank stored in 'windowOrderHistory'.
        // Windows seen before reclaim their old spots; new windows are added to the end.
        let sortedWindows = newWindows.sorted { (winA, winB) -> Bool in
            let rankA = windowOrderHistory[winA.windowID] ?? Int.max
            let rankB = windowOrderHistory[winB.windowID] ?? Int.max
            return rankA < rankB
        }
        
        // Step 3: Update the State.
        self.windows = sortedWindows
        
        // 4. Update History (SAFE MODE)
                // FIX: We do NOT overwrite existing history here.
                // If we did, a temporary "blink" (where a window disappears for 1 second)
                // would reset its rank to 0, causing collisions and swapping when it returns.
                
                // We only assign ranks to BRAND NEW windows we haven't seen before.
                var maxRank = windowOrderHistory.values.max() ?? -1
                
                for win in windows {
                    // If this window is not in our history book yet...
                    if windowOrderHistory[win.windowID] == nil {
                        // Add it to the very end of the line.
                        maxRank += 1
                        windowOrderHistory[win.windowID] = maxRank
                    }
                }
        
        // Step 5: Execute Layout.
        if hasNewWindow {
            // Smooth Entry Delay:
            // If a new window appeared, we wait 0.05 seconds before tiling.
            // This gives the new window time to render its initial frame (usually center screen),
            // allowing the animation system to slide it into place rather than teleporting it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.performLayoutNow()
            }
        } else {
            // If no new window appeared (just reordering or closing), tile immediately.
            performLayoutNow()
        }
    }
    
    // MARK: - 2. Reset Cache
    //
    // Clears the frame cache. This is typically called by SpaceManager when switching desktops
    // to force a recalculation of all window positions on the new space.
    func resetCache() {
        lastTargetFrames.removeAll()
    }
    
    // MARK: - 3. Manual Swapping
    //
    // Moves the currently focused window within the list order (e.g., swapping Master with Stack).
    //
    func moveFocusedWindow(_ direction: WindowAction) {
        // Identify the window the user is currently focused on.
        guard let focused = WindowDiscovery.shared.getFocusedWindow() else { return }
        guard let currentIndex = windows.firstIndex(where: { $0.windowID == focused.windowID }) else { return }
        
        var newIndex = currentIndex
        
        // Calculate the new index based on the direction command.
        switch direction {
        case .moveLeft:  newIndex = 0              // Promote to Master position
        case .moveRight: newIndex = 1              // Demote to top of Stack
        case .moveUp:    newIndex = currentIndex - 1
        case .moveDown:  newIndex = currentIndex + 1
        default: return
        }
        
        // Ensure the new index is within valid bounds.
        newIndex = min(max(newIndex, 0), windows.count - 1)
        
        // Perform the swap if the index actually changed.
        if newIndex != currentIndex {
            print("Swapping [\(currentIndex)] -> [\(newIndex)]")
            windows.swapAt(currentIndex, newIndex)
            
            // Critical Step: Update History immediately.
            // We must update 'windowOrderHistory' right now so that this manual change is remembered.
            // If we don't do this, switching spaces would revert the window to its old position.
            for (index, win) in windows.enumerated() {
                windowOrderHistory[win.windowID] = index
            }
            
            applyLayout()
        }
    }

    // MARK: - 4. Apply Layout (Debounced)
    //
    // Schedules a layout update. It uses a "debounce" timer to prevent rapid-fire updates
    // if the user is dragging or resizing a window manually.
    //
    func applyLayout() {
        // Do not interfere if the SpaceManager is currently throwing a window to another desktop.
        if SpaceManager.shared.isThrowing { return }
        
        debounceTimer?.cancel()
        
        let item = DispatchWorkItem { [weak self] in
            self?.performLayoutNow()
        }
        
        debounceTimer = item
        // Wait 0.5 seconds after the last request before actually running the layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50, execute: item)
    }
    
    // MARK: - 5. Perform Layout
    //
    // The core function that calculates geometry and commands the animator.
    //
    private func performLayoutNow() {
        
        // Global Mouse Guard:
        // We check the physical hardware state of the left mouse button.
        // If the user is holding the mouse down (dragging/clicking), we pause operations.
        // Moving a window while the user is dragging it causes conflicts with the OS.
        if CGEventSource.buttonState(.combinedSessionState, button: .left) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.performLayoutNow()
            }
            return
        }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Iterate through each connected display.
        for screen in screens {
            // Calculate the usable area, leaving a gap around the edges.
            let visible = screen.visibleFrame.insetBy(dx: gap, dy: gap)

            // Filter the window list to include only those currently visible on this screen.
            let activeWindows = windows.filter { $0.isOnScreen }
            
            if activeWindows.isEmpty { continue }
            
            // Mathematical Calculation:
            // Determine the exact frame (x, y, width, height) for every window based on the algorithm.
            let rects = calculateMasterStackRects(bounds: visible, windows: activeWindows)
            
            // Assign the calculated frames to the windows.
            for (i, win) in activeWindows.enumerated() {
                guard let ax = win.axElement else { continue }
                if i < rects.count {
                    let target = rects[i]
                    let id = win.windowID
                    
                    // Optimization:
                    // Compare the new target frame with the last one we applied.
                    // If the difference is negligible (< 1 pixel), we skip the update to save CPU.
                    if let last = lastTargetFrames[id] {
                        if abs(last.minX - target.minX) < 1.0 &&
                           abs(last.minY - target.minY) < 1.0 &&
                           abs(last.width - target.width) < 1.0 &&
                           abs(last.height - target.height) < 1.0 {
                            continue
                        }
                    }

                    // Update cache and trigger the animation.
                    lastTargetFrames[id] = target
                    WindowAnimator.shared.animate(window: ax, to: target)
                }
            }
        }
    }
    
    // MARK: - 6. Master-Stack Calculation
    //
    // Implements the specific tiling algorithm:
    // - Window 0 (Master) takes the left half of the screen.
    // - Windows 1...N (Stack) share the right half, split vertically.
    //
    private func calculateMasterStackRects(bounds: CGRect, windows: [ManagedWindow]) -> [CGRect] {
        if windows.isEmpty { return [] }
        if windows.count == 1 { return [bounds] }
        
        var rects: [CGRect] = []
        
        // --- Calculate Master Column ---
        let masterApp = windows[0]
        
        // Check if the Master app has a specific minimum width requirement.
        let desiredWidth = appMinSizes[masterApp.ownerName] ?? genericMinW
        
        // Default to 50% split, but expand if the app requires more space.
        var masterWidth = bounds.width / 2.0
        if masterWidth < desiredWidth { masterWidth = desiredWidth }
        
        // Cap the master width so the stack column doesn't become too thin.
        let minStackWidth: CGFloat = 400.0
        let maxMasterWidth = bounds.width - minStackWidth - gap
        if masterWidth > maxMasterWidth { masterWidth = maxMasterWidth }
        
        // Create the Master Rectangle.
        let masterRect = CGRect(x: bounds.minX, y: bounds.minY, width: masterWidth, height: bounds.height)
        rects.append(masterRect)
        
        // --- Calculate Stack Column ---
        let stackX = bounds.minX + masterWidth + gap
        let stackWidth = bounds.width - masterWidth - gap
        let stackCount = CGFloat(windows.count - 1)
        
        if stackCount <= 0 { return rects }
        
        // Divide the vertical space equally among the stack windows.
        let stackHeight = (bounds.height - (gap * (stackCount - 1))) / stackCount
        
        for i in 0..<Int(stackCount) {
            let yPos = bounds.minY + CGFloat(i) * (stackHeight + gap)
            let stackRect = CGRect(x: stackX, y: yPos, width: stackWidth, height: stackHeight)
            rects.append(stackRect)
        }
        
        return rects
    }
}
