//
//  ManagedWindow.swift
//  HyperMac
//
//  Lightweight model representing a real macOS window discovered through
//  CoreGraphics (CGWindowList) and paired with an optional AXUIElement for
//  Accessibility-based control. This struct stores static metadata and the
//  most recent frame snapshot for layout and animation decisions.
//
//  Used by:
//  - WindowDiscovery: builds ManagedWindow objects from CGWindow metadata
//  - LayoutEngine: determines layout and window order
//  - WindowAnimator: applies animated AX frame updates
//

import Foundation
import ApplicationServices

struct ManagedWindow {

    // Unique system-assigned window ID (CGWindowID).
    let windowID: CGWindowID

    // Process owning the window.
    let ownerPID: pid_t
    
    // Name of the owning application (e.g., “Google Chrome”).
    let ownerName: String
    
    // Optional bundle identifier (e.g., com.apple.Safari).
    let appBundleID: String?
    
    // Last-known window frame, from CGWindow API.
    // Used to determine if a window is visible and suitable for tiling.
    let frame: CGRect
    
    // Whether the window is currently visible on at least one screen.
    let isOnScreen: Bool

    // AX element for controlling the window’s position and size.
    // May be nil for windows that don’t support AX.
    let axElement: AXUIElement?
}
