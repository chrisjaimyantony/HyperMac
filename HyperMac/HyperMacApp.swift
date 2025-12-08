//
//  HyperMacApp.swift
//  HyperMac
//
//  This is the starting point of the application.
//  Because we are building a system utility (Window Manager) and not a
//  standard app with windows, we need to bypass some default SwiftUI behaviors.
//
//  Created by Chris on 26/11/25.
//

import SwiftUI

@main
struct HyperMacApp: App {

    // This connects the modern SwiftUI lifecycle to the older AppKit lifecycle.
    // We need AppKit (AppDelegate) because it handles the low-level system events,
    // menu bar icons, and accessibility permissions better than SwiftUI does.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {

        // HyperMac runs in the background and does not have a main window.
        // However, SwiftUI requires us to return at least one "Scene".
        // We return a "Settings" scene with an EmptyView so nothing appears on screen.
        Settings {
            EmptyView()
        }
    }
}
