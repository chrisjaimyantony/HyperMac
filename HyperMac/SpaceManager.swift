//
//  SpaceManager.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import CoreGraphics

class SpaceManager {
    static let shared = SpaceManager()
    
    var isThrowing: Bool = false
    private let spaceTransitionDelay = 0.8
    
    // Key Codes
    private let kCtrl: CGKeyCode = 59
    private let kShift: CGKeyCode = 56
    private let kOpt: CGKeyCode = 58
    private let kCmd: CGKeyCode = 55
    private let kLeftArrow: CGKeyCode = 123
    private let kRightArrow: CGKeyCode = 124
    
    // SWITCH SPACE
    func switchToSpace(_ number: Int) {
        cleanseModifiers()
        postKey(keyCode: kCtrl, down: true)
        let keyMap: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22]
        if let code = keyMap[number] {
            postKey(keyCode: code, down: true)
            usleep(20000)
            postKey(keyCode: code, down: false)
        }
        postKey(keyCode: kCtrl, down: false)
        restorePhysicalModifiers()
    }
    
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
    
    // THROW WINDOW
    func moveWindowToSpace(_ window: ManagedWindow, spaceNumber: Int) {
        // We need the raw AXElement to move it
        guard let ax = window.axElement else { return }
        
        self.isThrowing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.isThrowing = false }
        
        // ACTIVATE APP
        let appPID = window.ownerPID
        if let runningApp = NSRunningApplication(processIdentifier: appPID) {
            runningApp.activate()
            usleep(50000)
        }
        
        // THE CENTER SNAP
        // We calculate a safe "Staging Area" in the middle of the screen.
        // This guarantees the title bar is accessible and not hidden by the notch/menu bar.
        if let screenFrame = NSScreen.main?.frame {
            let safeWidth: CGFloat = 800
            let safeHeight: CGFloat = 600
            let safeX = (screenFrame.width - safeWidth) / 2.0
            let safeY = (screenFrame.height - safeHeight) / 2.0
            
            let stagingRect = CGRect(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
            
            // Teleport using Accessibility API
            // We use the raw AXWindowController logic here locally or call shared if available
            // Assuming AXWindowController is robust:
            AXWindowController.shared.setFrame(for: ax, to: stagingRect)
            
            // Wait for visual update
            usleep(100000)
        }
        
        // RE-READ FRAME
        // We must ask where it actually ended up
        var newFrame = window.frame
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        newFrame = CGRect(origin: pos, size: size)
        
        let originalMouse = CGEvent(source: nil)?.location ?? .zero
        
        // GRIP
        let gripPoint = CGPoint(x: newFrame.midX + 200, y: newFrame.minY + 15)
        DispatchQueue.global(qos: .userInteractive).async {
            
            // APPROACH & CLICK
            self.postMouse(event: .mouseMoved, point: gripPoint, clean: true)
            usleep(50000)
            self.postMouse(event: .leftMouseDown, point: gripPoint, clean: true)
            usleep(100000) // Solid hold
            
            // DRAG
            let dragDist: CGFloat = 80.0
            let steps = 8
            for i in 1...steps {
                let currentX = gripPoint.x + (dragDist / CGFloat(steps) * CGFloat(i))
                self.postMouse(event: .leftMouseDragged, point: CGPoint(x: currentX, y: gripPoint.y), clean: true)
                usleep(10000)
            }
            
            let holdPoint = CGPoint(x: gripPoint.x + dragDist, y: gripPoint.y)
            usleep(150000) // Anchor
            
            // SWITCH
            self.switchToSpace(spaceNumber)
            
            // DROP
            usleep(useconds_t(self.spaceTransitionDelay * 1000000))
            
            self.postMouse(event: .leftMouseUp, point: holdPoint, clean: true)
            usleep(50000)
            self.postMouse(event: .mouseMoved, point: originalMouse, clean: true)
            
            // UNLOCK & SCAN
            DispatchQueue.main.async {
                self.isThrowing = false
                            
                // Checks constantly for 1.2 seconds
                // This guarantees we catch the window even if it is slow to register on the new desktop.
                WindowDiscovery.shared.startBurstScan()
                            
                // Also reset the Layout Engine cache so it doesn't ignore the new positions
                LayoutEngine.shared.resetCache()
            }
        }
    }
    
    // Helpers
    private func cleanseModifiers() {
        let mods: [CGKeyCode] = [58, 61, 56, 60, 55, 54]
        for key in mods {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
            event?.flags = []
            event?.post(tap: CGEventTapLocation.cghidEventTap)
        }
        usleep(10000)
    }
    
    private func restorePhysicalModifiers() {}
    
    private func postKey(keyCode: CGKeyCode, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
        if down && keyCode == kCtrl { event?.flags = .maskControl }
        else if !down && keyCode == kCtrl { event?.flags = [] }
        else if down { event?.flags = .maskControl }
        else { event?.flags = [] }
        event?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    
    private func postMouse(event: CGEventType, point: CGPoint, clean: Bool = false) {
        let e = CGEvent(mouseEventSource: nil, mouseType: event, mouseCursorPosition: point, mouseButton: .left)
        if clean { e?.flags = [] }
        e?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
