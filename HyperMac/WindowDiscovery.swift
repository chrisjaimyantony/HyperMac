//
//  WindowDiscovery.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL: "Burst Mode" (Fixes Occupied-to-Occupied Tiling Lag)
//

import Foundation
import Cocoa
import ApplicationServices

private let AXWindowNumberAttributeName: CFString = "AXWindowNumber" as CFString

class WindowDiscovery {

    static let shared = WindowDiscovery()
    var onWindowsChanged: (([ManagedWindow]) -> Void)?
    
    private let scanQueue = DispatchQueue(label: "com.hypermac.discovery", qos: .utility)
    private var isRunning = false
    
    private let browserWhitelist: [String] = [
        "Brave Browser", "Google Chrome", "Arc", "Safari", "Firefox", "Microsoft Edge"
    ]

    func start() {
        if isRunning { return }
        isRunning = true
        scanQueue.async { [weak self] in self?.scanLoop() }
    }

    func stop() { isRunning = false }

    private func scanLoop() {
        guard isRunning else { return }
        let newWindows = self.performScan(forceVisible: false)
        
        DispatchQueue.main.async { [weak self] in
            self?.onWindowsChanged?(newWindows)
        }
        
        scanQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.scanLoop()
        }
    }
    
    func startBurstScan() {
        print("Starting Burst Scan...")
        for i in 0...6 {
            let delay = Double(i) * 0.2 // 0.0, 0.2, 0.4 ... 1.2s
            scanQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                
                // Force Visible = True 
                let newWindows = self.performScan(forceVisible: true)
                
                DispatchQueue.main.async {
                    self.onWindowsChanged?(newWindows)
                }
            }
        }
    }
    
    // Single Force Scan (Keep for compatibility)
    func forceImmediateScan() {
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            let newWindows = self.performScan(forceVisible: true)
            DispatchQueue.main.async { self.onWindowsChanged?(newWindows) }
        }
    }

    private func performScan(forceVisible: Bool) -> [ManagedWindow] {
        guard AXIsProcessTrusted() else { return [] }
        var collected: [ManagedWindow] = []
        
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isHidden }
        var onscreenIDs = Set<CGWindowID>()
        if !forceVisible {
            onscreenIDs = currentOnscreenWindowIDs()
        }
        
        let screenFrame = NSScreen.main?.frame ?? .zero

        for app in apps {
            let appName = app.localizedName ?? "Unknown"
            let isVIP = browserWhitelist.contains(appName)
            
            let appAX = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appAX, kAXWindowsAttribute as CFString, &value)
            guard result == .success, let windows = value as? [AXUIElement] else { continue }

            for axWin in windows {
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXRoleAttribute as CFString, &roleRef)
                if (roleRef as? String) != (kAXWindowRole as String) { continue }

                var subroleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleRef)
                let subrole = subroleRef as? String ?? ""
                if ["AXSystemDialog", "AXFloatingWindow", "AXDialog"].contains(subrole) { continue }

                var minRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minRef)
                if (minRef as? Bool) == true { continue }

                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)
                var pos = CGPoint.zero
                var size = CGSize.zero
                if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
                if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
                
                let frame = CGRect(origin: pos, size: size)
                if frame.width < 50 || frame.height < 50 { continue }

                var isOnScreen = false
                if screenFrame.intersects(frame) { isOnScreen = true }
                
                var windowID: CGWindowID = 0
                var winNumRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, AXWindowNumberAttributeName, &winNumRef)
                if let num = winNumRef as? NSNumber { windowID = CGWindowID(num.uint32Value) }
                
                if !forceVisible && !isVIP && windowID != 0 {
                    if !onscreenIDs.contains(windowID) { isOnScreen = false }
                }
                if forceVisible && screenFrame.intersects(frame) { isOnScreen = true }

                if windowID == 0 { windowID = CGWindowID(UInt32(truncatingIfNeeded: CFHash(axWin))) }

                let w = ManagedWindow(
                    windowID: windowID,
                    ownerPID: app.processIdentifier,
                    ownerName: appName,
                    appBundleID: app.bundleIdentifier,
                    frame: frame,
                    isOnScreen: isOnScreen,
                    axElement: axWin
                )
                collected.append(w)
            }
        }
        return collected
    }

    private func currentOnscreenWindowIDs() -> Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return ids }
        for info in infoList {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer == 0, let num = info[kCGWindowNumber as String] as? NSNumber {
                ids.insert(CGWindowID(num.uint32Value))
            }
        }
        return ids
    }
    
    func getFocusedWindow() -> ManagedWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appAX = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appAX, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        if result == .success, let axWin = focusedWindowRef as! AXUIElement? {
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)
            var pos = CGPoint.zero
            var size = CGSize.zero
            if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
            if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
            var windowID: CGWindowID = 0
            var winNumRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWin, AXWindowNumberAttributeName, &winNumRef)
            if let num = winNumRef as? NSNumber { windowID = CGWindowID(num.uint32Value) }
            if windowID == 0 { windowID = CGWindowID(UInt32(truncatingIfNeeded: CFHash(axWin))) }
            
            return ManagedWindow(
                windowID: windowID,
                ownerPID: frontApp.processIdentifier,
                ownerName: frontApp.localizedName ?? "Unknown",
                appBundleID: frontApp.bundleIdentifier,
                frame: CGRect(origin: pos, size: size),
                isOnScreen: true,
                axElement: axWin
            )
        }
        return nil
    }
}
