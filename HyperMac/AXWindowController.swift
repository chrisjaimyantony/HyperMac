//
//  AXWindowController.swift
//  HyperMac
//
//  Provides a thin abstraction over macOS Accessibility APIs (AXUIElement)
//  for positioning and resizing application windows.
//  This controller handles:
//  - Converting CGRects into AX values
//  - Setting window size and position
//  - Fetching all AX-accessible windows from running apps
//
//  Created by Chris on 27/11/25.
//

import Foundation
import Cocoa
import ApplicationServices

class AXWindowController {
    
    static let shared = AXWindowController()
    
    // Sets a window's position and size using AX attributes.
    // This is the low-level primitive used by the LayoutEngine and WindowAnimator.
    func setFrame(for window: AXUIElement, to frame: CGRect) {
        
        // Convert rect into AX-friendly values.
        var pos  = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        
        guard let posValue  = AXValueCreate(.cgPoint, &pos) else {
            print("AXWindowController: Failed to create AX CGPoint value.")
            return
        }
        
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            print("AXWindowController: Failed to create AX CGSize value.")
            return
        }
        
        // Set window position.
        let posResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            posValue
        )
        
        // Set window size.
        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        
        if posResult == .success && sizeResult == .success {
            print("AXWindowController: Frame applied → \(frame)")
        } else {
            print("AXWindowController: Failed to apply AX frame. Check permissions or AX validity.")
        }
    }
    
    // Fetches all AX-accessible top-level windows from all running apps.
    // Apps must have Accessibility enabled and use the `.regular` activation policy.
    func fetchWindows() -> [AXUIElement] {
        
        var allWindows: [AXUIElement] = []
        
        // Iterate through running GUI apps
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            
            let appAX = AXUIElementCreateApplication(app.processIdentifier)
            var rawValue: CFTypeRef?
            
            let result = AXUIElementCopyAttributeValue(
                appAX,
                kAXWindowsAttribute as CFString,
                &rawValue
            )
            
            if result == .success,
               let windows = rawValue as? [AXUIElement] {
                allWindows.append(contentsOf: windows)
            }
        }
        
        print("AXWindowController: AX-accessible windows found: \(allWindows.count)")
        return allWindows
    }
}
