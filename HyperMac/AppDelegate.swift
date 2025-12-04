//
//  AppDelegate.swift
//  HyperMac
//
//  Entry point for the HyperMac application.
//  This file is responsible for:
//  - Setting the macOS app activation policy (no Dock icon)
//  - Initializing core managers (layout, hotkeys, window discovery, AX)
//  - Ensuring Accessibility permissions are granted before running
//  - Starting the window scanning loop
//  - Handling cleanup on termination
//
//  Created by Chris on 27/11/25.
//

import Cocoa // AppKit APIs for macOS apps

class AppDelegate: NSObject, NSApplicationDelegate {

    // Menu bar controller (status item at top-right)
    private var statusBarController: StatusBarController?

    // Core manager singletons
    let accessibilityManager = AccessibilityManager()
    let windowDiscovery = WindowDiscovery.shared
    let layoutEngine = LayoutEngine.shared
    let hotkeyManager = HotkeyManager.shared
    let axController = AXWindowController.shared

    // Called when the application has finished launching
    func applicationDidFinishLaunching(_ notification: Notification) {

        // Run as an accessory app:
        // - No Dock icon
        // - No entry in Cmd+Tab
        NSApp.setActivationPolicy(.accessory)

        // Create the menu bar icon and menu
        statusBarController = StatusBarController()

        // Request (or verify) Accessibility permissions.
        accessibilityManager.ensureAccessibilityPermissions()

        // Only begin scanning and managing windows once permissions are granted.
        accessibilityManager.whenTrusted { [weak self] in
            guard let self = self else { return }

            // When window list changes, update layout engine
            self.windowDiscovery.onWindowsChanged = { windows in
                self.layoutEngine.updateWindows(windows)
                self.layoutEngine.applyLayout()
            }

            // Start watching for windows
            self.windowDiscovery.start()
        }

        // Start global hotkey listener
        hotkeyManager.startListening()
    }

    // Called when the app is about to quit
    func applicationWillTerminate(_ notification: Notification) {

        // Stop scanning and remove event taps
        windowDiscovery.stop()
        hotkeyManager.stopListening()
    }
}
