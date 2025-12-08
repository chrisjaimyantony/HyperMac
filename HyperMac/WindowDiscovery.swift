//
//  WindowDiscovery.swift
//  HyperMac
//
//  The central scanning and monitoring unit for the application.
//  Responsible for detecting open windows, filtering out system noise,
//  and monitoring user interactions (like dragging) to trigger layout updates.
//
//  Created by Chris on 27/11/25.
//

import Foundation
import Cocoa
import ApplicationServices

private let AXWindowNumberAttributeName: CFString = "AXWindowNumber" as CFString

// 1. GLOBAL CALLBACK (Must be outside the class)
// Executes every time the user manually moves or resizes a window.
func observerCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    // Notifies the Layout Engine that a manual change has occurred.
    // This triggers the layout recalculation to ensure consistency.
    LayoutEngine.shared.applyLayout()
}

class WindowDiscovery {

    static let shared = WindowDiscovery()
    var onWindowsChanged: (([ManagedWindow]) -> Void)?
    
    private let scanQueue = DispatchQueue(label: "com.hypermac.discovery", qos: .utility)
    private var isRunning = false
    
    // Monitors global mouse events to detect when a drag operation completes.
    // Added in v0.2 for the "Snap Back" feature.
    private var mouseMonitor: Any?
    
    // Defines a list of browser applications that receive special handling.
    private let browserWhitelist: [String] = [
        "Brave Browser", "Google Chrome", "Arc", "Safari", "Firefox", "Microsoft Edge"
    ]

    // Initializes the background scanning loop and registers global event monitors.
    func start() {
        if isRunning { return }
        isRunning = true
        
        // Begins the recursive scanning loop on a background queue.
        scanQueue.async { [weak self] in self?.scanLoop() }
        
        // Registers a global listener for the 'Left Mouse Up' event.
        // Assumes that releasing the mouse button indicates the end of a window drag operation.
        // Waits 0.2 seconds before enforcing the layout to ensure the window snaps back into place.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            
            // Checks if the SpaceManager is currently performing a window throw.
            // If so, prevents the snap-back logic to avoid conflicts.
            if SpaceManager.shared.isThrowing { return }
            
            // Schedules a layout enforcement on the main thread.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                print("Mouse Up detected: Enforcing Tiling Layout...")
                LayoutEngine.shared.applyLayout()
            }
        }
    }

    // Terminates the scanning loop and removes global event monitors.
    func stop() {
        isRunning = false
        
        // Removes the mouse monitor to prevent memory leaks or unwanted behavior.
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // Continuously queries the system for window updates.
    private func scanLoop() {
        guard isRunning else { return }
        
        // Performs the scan without forcing off-screen windows to be visible.
        let newWindows = self.performScan(forceVisible: false)
        
        // Dispatches the results to the main thread for processing.
        DispatchQueue.main.async { [weak self] in
            self?.onWindowsChanged?(newWindows)
        }
        
        // Schedules the next scan iteration after a 1.5-second delay.
        scanQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.scanLoop()
        }
    }
    
    // Triggers a rapid sequence of scans.
    // Intended for use when switching spaces to quickly capture windows that may be fading in.
    func startBurstScan() {
        print("Starting Burst Scan...")
        for i in 0...6 {
            let delay = Double(i) * 0.2
            scanQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                
                // Forces a check of all windows, including those potentially off-screen during transition.
                let newWindows = self.performScan(forceVisible: true)
                
                DispatchQueue.main.async {
                    self.onWindowsChanged?(newWindows)
                }
            }
        }
    }
    
    // Performs an immediate, one-off scan.
    func forceImmediateScan() {
        scanQueue.async { [weak self] in
            guard let self = self else { return }
            let newWindows = self.performScan(forceVisible: true)
            DispatchQueue.main.async { self.onWindowsChanged?(newWindows) }
        }
    }

    // Queries the Accessibility API to build a list of currently managed windows.
    // Filters out system elements, minimized windows, and invisible items.
    private func performScan(forceVisible: Bool) -> [ManagedWindow] {
        // Ensures the application has the necessary accessibility permissions.
        guard AXIsProcessTrusted() else { return [] }
        var collected: [ManagedWindow] = []
        
        // Retrieves all regular, non-hidden applications.
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isHidden }
        var onscreenIDs = Set<CGWindowID>()
        
        // If not forcing visibility, checks CoreGraphics for the list of windows actually on screen.
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
                // Role Filter: Ensures the element is actually a "Window".
                var roleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXRoleAttribute as CFString, &roleRef)
                if (roleRef as? String) != (kAXWindowRole as String) { continue }

                // Subrole Filter: Excludes system dialogs and floating bubbles.
                var subroleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXSubroleAttribute as CFString, &subroleRef)
                let subrole = subroleRef as? String ?? ""
                if ["AXSystemDialog", "AXFloatingWindow", "AXDialog"].contains(subrole) { continue }

                // Minimized Filter: Excludes windows that are currently minimized to the Dock.
                var minRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXMinimizedAttribute as CFString, &minRef)
                if (minRef as? Bool) == true { continue }
                
                // Ghost Filter: Excludes windows with empty titles (often invisible background processes).
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                let title = titleRef as? String ?? ""
                if title.isEmpty { continue }

                // Splash Filter: Excludes windows that cannot be resized (e.g., splash screens).
                var isResizable: DarwinBoolean = false
                let sizeWritable = AXUIElementIsAttributeSettable(axWin, kAXSizeAttribute as CFString, &isResizable)
                if sizeWritable == .success && isResizable == false { continue }

                // Frame Extraction: Retrieves Position and Size.
                var posRef: CFTypeRef?
                var sizeRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef)
                AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef)
                var pos = CGPoint.zero
                var size = CGSize.zero
                if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
                if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
                
                let frame = CGRect(origin: pos, size: size)
                // Size Filter: Ignores tiny windows that are likely tooltips or overlays.
                if frame.width < 50 || frame.height < 50 { continue }

                var isOnScreen = false
                if screenFrame.intersects(frame) { isOnScreen = true }
                
                // ID Extraction: Retrieves the unique CGWindowID.
                var windowID: CGWindowID = 0
                var winNumRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axWin, AXWindowNumberAttributeName, &winNumRef)
                if let num = winNumRef as? NSNumber { windowID = CGWindowID(num.uint32Value) }
                
                // Visibility Verification: Uses CoreGraphics to confirm the window is truly visible.
                if !forceVisible && !isVIP && windowID != 0 {
                    if !onscreenIDs.contains(windowID) { isOnScreen = false }
                }
                if forceVisible && screenFrame.intersects(frame) { isOnScreen = true }

                // Fallback ID Generation: Generates a hash if no WindowID is provided.
                if windowID == 0 { windowID = CGWindowID(UInt32(truncatingIfNeeded: CFHash(axWin))) }
                
                // Observer Attachment:
                // Attaches a listener to the window if it is visible, to detect manual movement.
                if isOnScreen {
                    self.setupObserver(for: app.processIdentifier, windowElement: axWin)
                }

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

    // Uses CoreGraphics to retrieve a list of window IDs currently drawn on the screen.
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
    
    // Attaches a "Wiretap" (AXObserver) to the window to detect manual dragging.
    private func setupObserver(for appPID: pid_t, windowElement: AXUIElement) {
        var observer: AXObserver?
        
        // Creates the observer pointing to the global callback function.
        let result = AXObserverCreate(appPID, observerCallback, &observer)
        
        guard result == .success, let obs = observer else { return }
        
        // Registers notifications for "Moved" and "Resized" events.
        AXObserverAddNotification(obs, windowElement, kAXMovedNotification as CFString, nil)
        AXObserverAddNotification(obs, windowElement, kAXResizedNotification as CFString, nil)
        
        // Adds the observer to the main run loop.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }
    
    // Retrieves the currently focused window from the frontmost application.
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
