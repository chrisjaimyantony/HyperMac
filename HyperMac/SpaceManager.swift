//
//  SpaceManager.swift
//  HyperMac
//
//  Controls macOS Mission Control Spaces for HyperMac.
//  Responsibilities:
//  - Switching between spaces (Ctrl + Number / Ctrl + Arrow)
//  - Throwing windows across spaces by simulating mouse drag + space switch
//  - Managing temporary blocking signals (isThrowing) to prevent layout repaint
//  - Handling low-level input simulation (mouse + keyboard events)
//
//  This component is heavily dependent on macOS HID event injection.
//  All window throws, space jumps, and modifier cleansing routines are
//  carefully tuned for stability across different apps.
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import CoreGraphics

class SpaceManager {
    
    static let shared = SpaceManager()
    
    // When true, LayoutEngine pauses layouting to avoid fighting the drag operation.
    var isThrowing: Bool = false
    
    // Delay after switching spaces to allow Mission Control animation to complete.
    private let spaceTransitionDelay = 0.8
    
    // Key codes for modifier reset / space switching.
    private let kCtrl: CGKeyCode = 59
    private let kShift: CGKeyCode = 56
    private let kOpt: CGKeyCode = 58
    private let kCmd: CGKeyCode = 55
    private let kLeftArrow: CGKeyCode = 123
    private let kRightArrow: CGKeyCode = 124

    // MARK: - Switch to Specific Space (Ctrl + Number)
    func switchToSpace(_ number: Int) {
        
        cleanseModifiers()
        
        postKey(keyCode: kCtrl, down: true)
        
        // Mission Control's default “Switch to Desktop N” key codes.
        let keyMap: [Int: CGKeyCode] = [
            1: 18, 2: 19, 3: 20, 4: 21,
            5: 23, 6: 22
        ]
        
        if let code = keyMap[number] {
            postKey(keyCode: code, down: true)
            usleep(20000)
            postKey(keyCode: code, down: false)
        }
        
        postKey(keyCode: kCtrl, down: false)
        restorePhysicalModifiers()
    }

    // MARK: - Arrow-Based Space Navigation
    func switchToNextSpace() {
        cleanseModifiers()
        performArrowSwitch(arrowKey: kRightArrow)
        restorePhysicalModifiers()
    }
    
    func switchToPreviousSpace() {
        cleanseModifiers()
        performArrowSwitch(arrowKey: kLeftArrow)
        restorePhysicalModifiers()
    }
    
    private func performArrowSwitch(arrowKey: CGKeyCode) {
        postKey(keyCode: kCtrl, down: true)
        postKey(keyCode: arrowKey, down: true)
        postKey(keyCode: arrowKey, down: false)
        postKey(keyCode: kCtrl, down: false)
    }

    // MARK: - Move (Throw) Window to Another Space
    //
    // Logic:
    // 1. Activate app
    // 2. Snap window to a safe center region
    // 3. Grab the title bar via synthetic drag
    // 4. Switch space mid-drag
    // 5. Release window in new space
    //
    func moveWindowToSpace(_ window: ManagedWindow, spaceNumber: Int) {
        
        guard let ax = window.axElement else { return }
        
        // Lock layout updates during throw.
        isThrowing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.isThrowing = false
        }
        
        // Activate owning application.
        if let app = NSRunningApplication(processIdentifier: window.ownerPID) {
            app.activate(options: [])
            usleep(50000)
        }
        
        // Stage window into a safe, centered location.
        if let screenFrame = NSScreen.main?.frame {
            let safeWidth: CGFloat = 800
            let safeHeight: CGFloat = 600
            
            let safeX = (screenFrame.width - safeWidth) / 2.0
            let safeY = (screenFrame.height - safeHeight) / 2.0
            
            let stagingRect = CGRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
            
            AXWindowController.shared.setFrame(for: ax, to: stagingRect)
            usleep(100000) // Allow redraw
        }
        
        // Re-read updated frame after staging.
        var newFrame = window.frame
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        
        AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &sizeRef)
        
        var pos = CGPoint.zero
        var size = CGSize.zero
        
        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue(s as! AXValue, .cgSize, &size)
        }
        
        newFrame = CGRect(origin: pos, size: size)
        
        //----------------------------
        // Begin Drag Gesture
        //----------------------------
        
        let originalMousePos = CGEvent(source: nil)?.location ?? .zero
        let gripPoint = CGPoint(x: newFrame.midX + 360, y: newFrame.minY + 15)
        
        DispatchQueue.global(qos: .userInteractive).async {
            
            // Move mouse to grip point.
            self.postMouse(event: .mouseMoved, point: gripPoint, clean: true)
            usleep(50000)
            
            // Mouse down (grab).
            self.postMouse(event: .leftMouseDown, point: gripPoint, clean: true)
            usleep(100000)

            // Drag rightwards to ensure window enters "drag state".
            let dragDistance: CGFloat = 80.0
            let steps = 8
            
            for i in 1...steps {
                let currX = gripPoint.x + (dragDistance / CGFloat(steps) * CGFloat(i))
                self.postMouse(event: .leftMouseDragged, point: CGPoint(x: currX, y: gripPoint.y), clean: true)
                usleep(10000)
            }
            
            let anchorPoint = CGPoint(x: gripPoint.x + dragDistance, y: gripPoint.y)
            usleep(150000)

            // Switch Mission Control space mid-drag.
            self.switchToSpace(spaceNumber)
            
            // Delay until space animation finishes.
            usleep(useconds_t(self.spaceTransitionDelay * 1_000_000))
            
            // Release mouse.
            self.postMouse(event: .leftMouseUp, point: anchorPoint, clean: true)
            usleep(50000)
            
            // Return cursor to original position.
            self.postMouse(event: .mouseMoved, point: originalMousePos, clean: true)
            
            // Final clean-up on main thread.
            DispatchQueue.main.async {
                self.isThrowing = false
                
                // Burst-scan to ensure new desktop registers the moved window.
                WindowDiscovery.shared.startBurstScan()
                
                // Reset Layout cache so new environment is respected.
                LayoutEngine.shared.resetCache()
            }
        }
    }

    // MARK: - Modifier / Input Helpers
    
    private func cleanseModifiers() {
        // Release all common modifier keys.
        let modifiers: [CGKeyCode] = [58, 61, 56, 60, 55, 54]
        
        for key in modifiers {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        usleep(10000)
    }
    
    private func restorePhysicalModifiers() {
        // Stub — intentionally empty.
        // (macOS automatically handles restoring real modifier states)
    }
    
    private func postKey(keyCode: CGKeyCode, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
        
        // Special-case: ensure Ctrl flag stays consistent.
        if down && keyCode == kCtrl {
            event?.flags = .maskControl
        } else if !down && keyCode == kCtrl {
            event?.flags = []
        } else if down {
            event?.flags = .maskControl
        } else {
            event?.flags = []
        }
        
        event?.post(tap: .cghidEventTap)
    }
    
    private func postMouse(event: CGEventType, point: CGPoint, clean: Bool = false) {
        let e = CGEvent(mouseEventSource: nil,
                        mouseType: event,
                        mouseCursorPosition: point,
                        mouseButton: .left)
        if clean { e?.flags = [] }
        e?.post(tap: .cghidEventTap)
    }
}
