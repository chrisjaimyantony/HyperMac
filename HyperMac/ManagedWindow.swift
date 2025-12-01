//
//  ManagedWindow.swift
//  HyperMac
//
//  A real macOS window with AXUIElement control
//

import Foundation
import ApplicationServices 

struct ManagedWindow {

    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let appBundleID: String?
    let frame: CGRect
    let isOnScreen: Bool
    
    let axElement: AXUIElement?
}
