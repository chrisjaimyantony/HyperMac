//
//  AccessibilityManager.swift
//  HyperMac
//
//  Manages macOS Accessibility permissions required for window control.
//  This file handles:
//  - Checking whether the app has AX access
//  - Prompting the system dialog if access is missing
//  - Polling until permissions are granted, then executing a callback
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import ApplicationServices

class AccessibilityManager {

    private var trustPollTimer: Timer?

    // Requests Accessibility permissions if missing, and prints status.
    // This triggers the macOS system dialog on first launch.
    func ensureAccessibilityPermissions() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true
        ]
        
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if !trusted {
            print("Please allow Accessibility access for HyperMac in System Settings.")
        } else {
            print("Permissions Granted.")
        }
    }

    // Executes the provided closure once Accessibility permissions are granted.
    // Used to delay window manager startup until AXIsProcessTrusted() becomes true.
    func whenTrusted(execute: @escaping () -> Void) {
        trustPollTimer?.invalidate()

        // If already trusted, run immediately.
        if AXIsProcessTrusted() {
            DispatchQueue.main.async { execute() }
            return
        }

        // Otherwise poll every 0.5 seconds until permissions are granted.
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            
            if AXIsProcessTrusted() {
                self?.trustPollTimer?.invalidate()
                self?.trustPollTimer = nil
                
                DispatchQueue.main.async { execute() }
            }
        }

        // Add to main run loop to ensure timer fires while UI updates occur.
        if let t = trustPollTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
}
