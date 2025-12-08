//
//  AppDelegate.swift
//  HyperMac
//
//  Entry point for the HyperMac application.
//  This file manages the app's lifecycle (starting up and shutting down).
//  It connects the different parts of the app like the scanner, layout engine, and menu bar.
//
//  Created by Chris on 27/11/25.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    // Controls the icon in the menu bar at the top right of the screen.
    private var statusBarController: StatusBarController?

    // These create the main parts of the app (managers) and keep them alive in memory.
    // If we didn't store them here, they would disappear immediately after the app starts.
    let accessibilityManager = AccessibilityManager()
    let windowDiscovery = WindowDiscovery.shared
    let layoutEngine = LayoutEngine.shared
    let hotkeyManager = HotkeyManager.shared
    let axController = AXWindowController.shared

    // This function runs automatically when the application finishes launching.
    func applicationDidFinishLaunching(_ notification: Notification) {

        // This hides the app from the Dock and the Command-Tab switcher.
        // It makes the app behave like a background utility.
        NSApp.setActivationPolicy(.accessory)

        // Create the icon in the menu bar.
        statusBarController = StatusBarController()

        // We need permission to control the computer's windows.
        // This checks if we have it, and asks the user if we don't.
        accessibilityManager.ensureAccessibilityPermissions()

        // Once the user gives permission, we start the main logic.
        accessibilityManager.whenTrusted { [weak self] in
            guard let self = self else { return }

            // 1. Connect the Scanner to the Layout Engine.
            // Whenever the scanner finds new windows, we send them to the Layout Engine
            // so it can calculate where they should go.
            self.windowDiscovery.onWindowsChanged = { windows in
                self.layoutEngine.updateWindows(windows)
                self.layoutEngine.applyLayout()
            }

            // 2. Start the continuous loop that looks for open windows.
            self.windowDiscovery.start()
            
            // 3. Detect when the user switches desktop spaces.
            // When you swipe to a new desktop, we need to update the layout immediately.
            // We add an observer to listen for this system event.
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(self.spaceChanged),
                name: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil
            )
        }

        // Turn on the keyboard shortcuts (like Alt+1, Alt+Enter).
        hotkeyManager.startListening()
    }
    
    // This function runs automatically when the desktop space changes.
    @objc func spaceChanged() {
        // We tell the scanner to run 6 times very quickly ("Burst Mode").
        // This helps us catch windows that might be loading or fading in on the new desktop.
        windowDiscovery.startBurstScan()
    }

    // This runs when the user quits the app.
    func applicationWillTerminate(_ notification: Notification) {
        // Stop the background scanning to save battery and memory.
        windowDiscovery.stop()
        
        // Stop listening for keyboard shortcuts.
        hotkeyManager.stopListening()
    }
}
