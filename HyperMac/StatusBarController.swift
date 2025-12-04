//
//  StatusBarController.swift
//  HyperMac
//
//  Creates and manages the macOS menu bar status item for HyperMac.
//  Responsibilities:
//  - Display a small icon/text in the menu bar
//  - Provide quick-access menu options (Reload Layout, Quit)
//  - Bridge user interactions to layout and app lifecycle actions
//
//  This class keeps HyperMac visible and accessible even without UI windows.
//
//  Created by Chris on 27/11/25.
//

import Cocoa

class StatusBarController {

    // The NSStatusItem displayed in the macOS menu bar.
    private var statusItem: NSStatusItem

    init() {

        // Create a variable-length menu bar item (text or image).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure the visual appearance of the button.
        if let button = statusItem.button {
            button.title = "⌘⌃"           // Placeholder text icon (replace with image if desired).
            button.toolTip = "HyperMac"   // Tooltip when hovering.
        }

        // Build the dropdown menu.
        let menu = NSMenu()

        // Option: manually re-run the tiling layout.
        menu.addItem(
            NSMenuItem(
                title: "Reload Layout",
                action: #selector(reloadLayout),
                keyEquivalent: "r"
            )
        )

        // Separator line.
        menu.addItem(NSMenuItem.separator())

        // Option: quit the app.
        menu.addItem(
            NSMenuItem(
                title: "Quit HyperMac",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        // Attach the menu to the menu bar icon.
        statusItem.menu = menu
    }

    // MARK: - Menu Actions

    // User pressed “Reload Layout”
    @objc private func reloadLayout() {
        LayoutEngine.shared.applyLayout()
    }

    // User pressed “Quit HyperMac”
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
