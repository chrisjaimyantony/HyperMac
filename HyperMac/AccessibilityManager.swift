//
//  AccessibilityManager.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import ApplicationServices

class AccessibilityManager{

    private var trustPollTimer: Timer?

    // Called at startup: prompts if needed
    func ensureAccessibilityPermissions(){
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

    // Call a closure once AXIsProcessTrusted() becomes true
    func whenTrusted(execute: @escaping () -> Void) {
        trustPollTimer?.invalidate()

        if AXIsProcessTrusted() {
            DispatchQueue.main.async { execute() }
            return
        }

        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            if AXIsProcessTrusted() {
                self?.trustPollTimer?.invalidate()
                self?.trustPollTimer = nil
                DispatchQueue.main.async { execute() }
            }
        }
        if let t = trustPollTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
}
