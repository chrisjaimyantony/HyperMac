//
//  StatusBarController.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//
//  Manages the Menu Bar icon (Status Item).
//  Updated: Uses the custom "logo_white" from the Assets folder.
//

import Cocoa

class StatusBarController {
    
    // The actual item in the menu bar system.
    private var statusItem: NSStatusItem!
    
    // Initialize and setup the menu.
    init() {
        // Create a variable length item (standard size).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            
            // We use the name exactly as it appears in your screenshot: "logo_white"
            if let logoImage = NSImage(named: "logo_white") {
                
                // 2. Resize it to 18x18 points.
                // to match the standard size of macOS menu bar icons.
                logoImage.size = NSSize(width: 18, height: 18)
                
                // 3. Enable "Template" mode.
                // This is important. It ignores the actual color of the image (white)
                // and lets macOS recolor it automatically.
                // It will be Black in Light Mode and White in Dark Mode.
                logoImage.isTemplate = true
                
                button.image = logoImage
            } else {
                // This prevents the menu bar space from being empty/invisible.
                button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "HyperMac")
            }
        }
        
        setupMenu()
    }
    
    // Construct the dropdown menu (Reload, Quit, etc).
    private func setupMenu() {
        let menu = NSMenu()
        
        // 1. Header (Version Info)
        let titleItem = NSMenuItem(title: "HyperMac Alpha", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Reload Button
        let reloadItem = NSMenuItem(title: "Reload Layout", action: #selector(reloadAction), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Quit Button
        let quitItem = NSMenuItem(title: "Quit HyperMac", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    // MARK: - Actions
    
    @objc private func reloadAction() {
        // 1. Clear cache
        LayoutEngine.shared.resetCache()
        
        // 2. Scan immediately
        WindowDiscovery.shared.forceImmediateScan()
        
        // 3. Apply layout
        LayoutEngine.shared.applyLayout()
    }
    
    @objc private func quitAction() {
        // Stop background threads
        WindowDiscovery.shared.stop()
        
        // Terminate app
        NSApplication.shared.terminate(nil)
    }
}
