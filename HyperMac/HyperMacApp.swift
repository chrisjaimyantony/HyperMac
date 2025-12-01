//
//  HyperMacApp.swift
//  HyperMac
//
//  Created by Chris on 26/11/25.
//

import SwiftUI

@main
struct HyperMacApp: App{
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        //Since now UI is present, a window screen isn't needed
        Settings{
            EmptyView()
        }
    }
}

