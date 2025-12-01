//
//  StatusBarController.swift
//  HyperMac
//
//  Provides a small menu bar icon with a menu for
//  reloading layout and quitting the app.
//

import Cocoa

class StatusBarController {

    // Reference to the item shown in the macOS menu bar.
    private var statusItem: NSStatusItem

    init() {

        // Create a variable-length menu bar item.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure the button (icon) appearance.
        if let button = statusItem.button {
            button.title = "⌘⌃"       // Simple text icon; you can replace with an image.
            button.toolTip = "HyperMac Tiler"
        }

        // Create the menu that opens when user clicks the icon.
        let menu = NSMenu()

        // Menu item: manually re-run layout.
        menu.addItem(NSMenuItem(title: "Reload Layout",
                                action: #selector(reloadLayout),
                                keyEquivalent: "r"))

        // Separator line.
        menu.addItem(NSMenuItem.separator())

        // Menu item: Quit the app.
        menu.addItem(NSMenuItem(title: "Quit HyperMac",
                                action: #selector(quit),
                                keyEquivalent: "q"))

        // Attach the menu to the status item.
        statusItem.menu = menu
    }

    // Called when user clicks "Reload Layout".
    @objc private func reloadLayout() {
        LayoutEngine.shared.applyLayout()
    }

    // Called when user clicks "Quit HyperMac".
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
