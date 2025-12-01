//
//  HotkeyManager.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL: All Commands Wired Up
//

import Cocoa

enum WindowAction {
    case focusLeft, focusRight, focusUp, focusDown
    case moveLeft, moveRight, moveUp, moveDown
    case workspace(Int)
    case moveToWorkspace(Int)
    case nextWorkspace, previousWorkspace
    case reload
    case quit
}

struct Keybind {
    let keyCode: Int
    let modifiers: CGEventFlags
}

class HotkeyManager {
    
    static let shared = HotkeyManager()
    private var eventTap: CFMachPort?
    
    // CONFIGURATION
    private var bindings: [(Keybind, WindowAction)] = [
        
        // --- RELOAD (Opt+Shift+R) ---
        (Keybind(keyCode: 15, modifiers: [.maskAlternate, .maskShift]), .reload),
        
        // --- QUIT (Opt+Shift+Q) ---
        (Keybind(keyCode: 12, modifiers: [.maskAlternate, .maskShift]), .quit),
        
        // --- MOVE WINDOW (Shift + HJKL) ---
        (Keybind(keyCode: 4, modifiers: [.maskAlternate, .maskShift]), .moveLeft),
        (Keybind(keyCode: 37, modifiers: [.maskAlternate, .maskShift]), .moveRight),
        (Keybind(keyCode: 40, modifiers: [.maskAlternate, .maskShift]), .moveUp),
        (Keybind(keyCode: 38, modifiers: [.maskAlternate, .maskShift]), .moveDown),
        
        // --- WORKSPACES (Opt + 1-4) ---
        (Keybind(keyCode: 18, modifiers: .maskAlternate), .workspace(1)),
        (Keybind(keyCode: 19, modifiers: .maskAlternate), .workspace(2)),
        (Keybind(keyCode: 20, modifiers: .maskAlternate), .workspace(3)),
        (Keybind(keyCode: 21, modifiers: .maskAlternate), .workspace(4)),
        
        // --- THROW (Opt + Shift + 1-4) ---
        (Keybind(keyCode: 18, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(1)),
        (Keybind(keyCode: 19, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(2)),
        (Keybind(keyCode: 20, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(3)),
        (Keybind(keyCode: 21, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(4)),
        
        // --- SWIPE (Opt + N/P) ---
        (Keybind(keyCode: 45, modifiers: .maskAlternate), .nextWorkspace),
        (Keybind(keyCode: 35, modifiers: .maskAlternate), .previousWorkspace),
    ]
    
    func startListening() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon in
                return HotkeyManager.shared.handle(event: event)
            },
            userInfo: nil
        )
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            let runLoop = RunLoop.current
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(runLoop.getCFRunLoop(), source, .commonModes)
        }
    }
    
    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
    
    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        for (bind, action) in bindings {
            if bind.keyCode == keyCode {
                if flags.contains(bind.modifiers) {
                    let bindingHasShift = bind.modifiers.contains(.maskShift)
                    let eventHasShift = flags.contains(.maskShift)
                    
                    if bindingHasShift == eventHasShift {
                        print("Action: \(action)")
                        execute(action)
                        return nil // Consume event
                    }
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    private func execute(_ action: WindowAction) {
        switch action {
        case .reload:
            print("Refreshing Layout...")
            LayoutEngine.shared.applyLayout()
            
        case .quit:
            print("Quitting HyperMac...")
            NSApp.terminate(nil)
            
        case .workspace(let num):
            SpaceManager.shared.switchToSpace(num)
            
        case .moveToWorkspace(let num):
            if let focused = WindowDiscovery.shared.getFocusedWindow() {
                SpaceManager.shared.moveWindowToSpace(focused, spaceNumber: num)
            }
            
        case .nextWorkspace:
            SpaceManager.shared.switchToNextSpace()
        case .previousWorkspace:
            SpaceManager.shared.switchToPreviousSpace()
            
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            LayoutEngine.shared.moveFocusedWindow(action)
            
        case .focusLeft, .focusRight, .focusUp, .focusDown:
            print("Focus logic todo")
        }
    }
}
