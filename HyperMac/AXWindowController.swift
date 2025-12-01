//
//  AXWindowController.swift
//  Handles positioning and sizing of windows via AX API
//

import Foundation
import Cocoa
import ApplicationServices

class AXWindowController {
    
    static let shared = AXWindowController()
    

    func setFrame(for window: AXUIElement, to frame: CGRect) {
        
        // Convert values into mutable &-passing vars
        var pos  = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        
        guard let posValue  = AXValueCreate(.cgPoint, &pos) else {
            print("Failed to create AX CGPoint"); return
        }
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            print("Failed to create AX CGSize"); return
        }
        
        // Apply new window position
        let posResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            posValue
        )
        
        // Apply new window size
        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        
        if posResult == .success && sizeResult == .success {
            print("Window frame applied → \(frame)")
        } else {
            print("AX command failed, check permissions")
        }
    }
    
    
    //  Fetch ALL AX windows from apps that expose accessibility
    func fetchWindows() -> [AXUIElement] {
        
        var allWindows: [AXUIElement] = []
        
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let appAX = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            
            let result = AXUIElementCopyAttributeValue(
                appAX,
                kAXWindowsAttribute as CFString,
                &value
            )
            
            if result == .success, let windows = value as? [AXUIElement] {
                allWindows.append(contentsOf: windows)
            }
        }
        
        print("AX-accessible windows found: \(allWindows.count)")
        return allWindows
    }
}
