//
//  AppDelegate.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//

import Cocoa  // AppKit APIs for macOS apps

class AppDelegate: NSObject, NSApplicationDelegate{

    // Holds the menu bar controller
    private var statusBarController: StatusBarController?

    // Core Managers
    let accessibilityManager = AccessibilityManager()
    let windowDiscovery = WindowDiscovery.shared
    let layoutEngine = LayoutEngine.shared
    let hotkeyManager = HotkeyManager.shared
    let axController = AXWindowController.shared

    // Called when app finishes launching
    func applicationDidFinishLaunching(_ notification: Notification){

        // Make app run as accessory, No Dock icon and no app switcher entry
        NSApp.setActivationPolicy(.accessory)

        // Create the menu bar icon (top right of macOS)
        statusBarController = StatusBarController()

        // Ask user to grant Accessibility permissions if not already
        accessibilityManager.ensureAccessibilityPermissions()

        // Only start scanning once Accessibility is trusted
        accessibilityManager.whenTrusted { [weak self] in
            guard let self else { return }
            self.windowDiscovery.onWindowsChanged = { windows in
                self.layoutEngine.updateWindows(windows)
                self.layoutEngine.applyLayout()
            }
            self.windowDiscovery.start()
        }

        // Listen for hotkeys
        hotkeyManager.startListening()
    }

    // Called when an app is quitting
    func applicationWillTerminate(_ notification: Notification){
        // Stop timers and taps to clean up
        windowDiscovery.stop()
        hotkeyManager.stopListening()
    }
}
