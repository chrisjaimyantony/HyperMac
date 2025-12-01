//
//  LayoutEngine.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL: Master-Stack + Safety + Cache Reset
//

import Cocoa
import ApplicationServices

class LayoutEngine {

    static let shared = LayoutEngine()
    private var windows: [ManagedWindow] = []
    
    // CACHE
    private var lastTargetFrames: [CGWindowID: CGRect] = [:]
    
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
        "Google Chrome": 500.0
    ]

    func updateWindows(_ newWindows: [ManagedWindow]) {
        var uniqueNew: [ManagedWindow] = []
        var seenIDs = Set<CGWindowID>()
        
        for w in newWindows {
            if !seenIDs.contains(w.windowID) {
                uniqueNew.append(w)
                seenIDs.insert(w.windowID)
            }
        }
        
        var updatedList: [ManagedWindow] = []
        for existing in self.windows {
            if let match = uniqueNew.first(where: { $0.windowID == existing.windowID }) {
                updatedList.append(match)
            }
        }
        for newWin in uniqueNew {
            if !self.windows.contains(where: { $0.windowID == newWin.windowID }) {
                updatedList.append(newWin)
            }
        }
        self.windows = updatedList
    }
    
    func resetCache() {
        lastTargetFrames.removeAll()
    }
    
    func moveFocusedWindow(_ direction: WindowAction) {
        guard let focused = WindowDiscovery.shared.getFocusedWindow() else { return }
        guard let currentIndex = windows.firstIndex(where: { $0.windowID == focused.windowID }) else { return }
        
        var newIndex = currentIndex
        switch direction {
        case .moveLeft:  newIndex = 0
        case .moveRight: newIndex = 1
        case .moveUp:    newIndex = currentIndex - 1
        case .moveDown:  newIndex = currentIndex + 1
        default: return
        }
        
        if newIndex < 0 { newIndex = 0 }
        if newIndex >= windows.count { newIndex = windows.count - 1 }
        
        if newIndex != currentIndex {
            windows.swapAt(currentIndex, newIndex)
            applyLayout()
        }
    }

    func promoteToMaster(windowID: CGWindowID) {
        guard let idx = windows.firstIndex(where: { $0.windowID == windowID }) else { return }
        if idx == 0 { return }
        let win = windows.remove(at: idx)
        windows.insert(win, at: 0)
        applyLayout()
    }

    func applyLayout() {
        if SpaceManager.shared.isThrowing { return }
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let vf = screen.visibleFrame.insetBy(dx: gap, dy: gap)

            // Group windows that are on this screen, not just globally isOnScreen
            let group = windows.filter { win in
                guard win.isOnScreen else { return false }
                return screen.frame.intersects(win.frame)
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
    
    private func calculateMasterStackRects(bounds: CGRect, windows: [ManagedWindow]) -> [CGRect] {
        if windows.isEmpty { return [] }
        if windows.count == 1 { return [bounds] }
        
        var rects: [CGRect] = []
        
        let masterApp = windows[0]
        let desiredWidth = appMinSizes[masterApp.ownerName] ?? genericMinW
        
        var masterWidth = bounds.width / 2.0
        if masterWidth < desiredWidth { masterWidth = desiredWidth }
        
        let minStackWidth: CGFloat = 400.0
        let maxMasterWidth = bounds.width - minStackWidth - gap
        
        if masterWidth > maxMasterWidth { masterWidth = maxMasterWidth }
        
        let masterRect = CGRect(x: bounds.minX, y: bounds.minY, width: masterWidth, height: bounds.height)
        rects.append(masterRect)
        
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
