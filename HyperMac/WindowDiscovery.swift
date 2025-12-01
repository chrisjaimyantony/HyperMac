//
//  WindowDiscovery.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL: "Trust Geometry" Mode (Fixes Tiling after Desktop Switch)
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
    
    // Browsers need extra leniency
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
        // Normal Scan: Strict visibility checks
        let newWindows = self.performScan(forceVisible: false)
        
        DispatchQueue.main.async { [weak self] in
            self?.onWindowsChanged?(newWindows)
        }
        
        scanQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.scanLoop()
        }
    }
    
    // CALLED BY SPACEMANAGER
    func forceImmediateScan() {
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            print("Force Scan: Trusting Geometry over Window Server")
            
            // FORCE VISIBLE
            let newWindows = self.performScan(forceVisible: true)
            
            DispatchQueue.main.async {
                self.onWindowsChanged?(newWindows)
            }
        }
    }

    private func performScan(forceVisible: Bool) -> [ManagedWindow] {
        guard AXIsProcessTrusted() else { return [] }
        var collected: [ManagedWindow] = []
        
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isHidden }
        
        // Only fetch system IDs if we are NOT forcing visibility
        var onscreenIDs = Set<CGWindowID>()
        if !forceVisible {
            onscreenIDs = currentOnscreenWindowIDs()
        }
        
        // Cache screen frame
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

                // GET GEOMETRY FIRST
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)

                var pos = CGPoint.zero
                var size = CGSize.zero
                if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
                if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
                
                let frame = CGRect(origin: pos, size: size)
                
                // For VIP browsers, allow very small frames during forceVisible
                if frame.width < 50 || frame.height < 50 {
                    if !(forceVisible && isVIP) {
                        continue
                    }
                }

                // VISIBILITY LOGIC
                var isOnScreen = false
                
                // Rule 1: Does it physically intersect the screen?
                if screenFrame.intersects(frame) {
                    isOnScreen = true
                }
                
                // Rule 2: Validation via Window Server (Skipped if forceVisible is true)
                var windowID: CGWindowID = 0
                var winNumRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, AXWindowNumberAttributeName, &winNumRef)
                if let num = winNumRef as? NSNumber { windowID = CGWindowID(num.uint32Value) }
                
                if !forceVisible && !isVIP && windowID != 0 {
                    // Normal mode: Double check with OS
                    if !onscreenIDs.contains(windowID) { isOnScreen = false }
                }
                
                // Force Mode overrides everything: If math says it's here, IT IS HERE.
                if forceVisible && screenFrame.intersects(frame) {
                    isOnScreen = true
                }

                // Fallback ID Generation
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
    
    // Focus Helper
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
