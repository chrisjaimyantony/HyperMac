//
//  HyperMacApp.swift
//  HyperMac
//
//  SwiftUI entry point for the HyperMac application.
//  This struct wires the SwiftUI lifecycle into the older NSApplication
//  lifecycle by attaching an AppDelegate. HyperMac does not present any
//  traditional UI windows, so the main scene hosts only an empty Settings
//  window to satisfy SwiftUI's requirements.
//
//  Created by Chris on 26/11/25.
//

import SwiftUI

@main
struct HyperMacApp: App {

    // Bridge SwiftUI lifecycle → AppKit lifecycle.
    // This allows AppDelegate to manage Accessibility, window scanning,
    // menu bar icon, hotkeys, and layout engine initialization.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {

        // Since HyperMac does not use any visible UI windows,
        // we declare only a minimal Settings scene that stays hidden.
        Settings {
            EmptyView()
        }
    }
}
