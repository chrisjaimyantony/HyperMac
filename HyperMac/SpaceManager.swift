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
    
    private let kCtrl: CGKeyCode = 59
    private let kLeftArrow: CGKeyCode = 123
    private let kRightArrow: CGKeyCode = 124
    
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
    }
    
    func switchToNextSpace() {
        cleanseModifiers()
        performArrowSwitch(arrowKey: kRightArrow)
    }
    
    func switchToPreviousSpace() {
        cleanseModifiers()
        performArrowSwitch(arrowKey: kLeftArrow)
    }
    
    private func performArrowSwitch(arrowKey: CGKeyCode) {
        postKey(keyCode: kCtrl, down: true)
        postKey(keyCode: arrowKey, down: true)
        postKey(keyCode: arrowKey, down: false)
        postKey(keyCode: kCtrl, down: false)
    }
    
    func moveWindowToSpace(_ window: ManagedWindow, spaceNumber: Int) {
        guard window.axElement != nil else { return }
        
        self.isThrowing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.isThrowing = false }
        
        // Activate App
        let appPID = window.ownerPID
        if let runningApp = NSRunningApplication(processIdentifier: appPID) {
            runningApp.activate()
            usleep(50000)
        }
        
        let frame = window.frame
        let originalMouse = CGEvent(source: nil)?.location ?? .zero
        
        let gripPoint = CGPoint(x: frame.minX + 80, y: frame.minY + 40)
        
        DispatchQueue.global(qos: .userInteractive).async {
            
          
            self.postMouse(event: .mouseMoved, point: gripPoint, clean: true)
            usleep(50000)
            
            self.postMouse(event: .leftMouseDown, point: gripPoint, clean: true)
            usleep(20000)
            self.postMouse(event: .leftMouseUp, point: gripPoint, clean: true)
            usleep(50000)
            
            self.postMouse(event: .leftMouseDown, point: gripPoint, clean: true)
            usleep(100000)
            
            let dragDist: CGFloat = 80.0
            let steps = 8
            for i in 1...steps {
                let currentX = gripPoint.x + (dragDist / CGFloat(steps) * CGFloat(i))
                self.postMouse(event: .leftMouseDragged, point: CGPoint(x: currentX, y: gripPoint.y), clean: true)
                usleep(10000)
            }
            
            let holdPoint = CGPoint(x: gripPoint.x + dragDist, y: gripPoint.y)
            usleep(200000)
           
            self.switchToSpace(spaceNumber)
            
        
            usleep(useconds_t(self.spaceTransitionDelay * 1000000))
            
            self.postMouse(event: .leftMouseUp, point: holdPoint, clean: true)
            usleep(50000)
            self.postMouse(event: .mouseMoved, point: originalMouse, clean: true)
            
            DispatchQueue.main.async {
                self.isThrowing = false

                WindowDiscovery.shared.forceImmediateScan()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    WindowDiscovery.shared.forceImmediateScan()
                    LayoutEngine.shared.applyLayout()

                    if let focused = WindowDiscovery.shared.getFocusedWindow(),
                       focused.windowID == window.windowID {
                        LayoutEngine.shared.promoteToMaster(windowID: window.windowID)
                    }
                }
            }
        }
    }
    
    // Helper to release physical modifiers virtually
    private func cleanseModifiers() {
        let mods: [CGKeyCode] = [58, 61, 56, 60, 55, 54] // Shift, Opt, Cmd
        for key in mods {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
            event?.flags = []
            event?.post(tap: CGEventTapLocation.cghidEventTap)
        }
        usleep(20000)
    }
    
    private func postKey(keyCode: CGKeyCode, down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
        
        // Strict Flag Control
        if down && keyCode == kCtrl {
            event?.flags = .maskControl
        } else if !down && keyCode == kCtrl {
            event?.flags = []
        } else if down {
            event?.flags = .maskControl
        } else {
            event?.flags = []
        }
        
        event?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    
    private func postMouse(event: CGEventType, point: CGPoint, clean: Bool = false) {
        let e = CGEvent(mouseEventSource: nil, mouseType: event, mouseCursorPosition: point, mouseButton: .left)
        if clean { e?.flags = [] }
        e?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

