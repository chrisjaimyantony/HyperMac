//
//  HotkeyManager.swift
//  HyperMac
//
//  Registers and handles all global hotkeys for HyperMac.
//  This component listens for keystrokes using a CGEvent tap and maps them
//  to window actions such as moving, swapping, throwing to spaces, reloading,
//  and quitting. The manager serves as the central routing layer for keyboard
//  navigation and workspace control.
//
//  Created by Chris on 27/11/25.
//

import Cocoa

// Represents all actions the hotkey system can trigger.
enum WindowAction {
    case focusLeft, focusRight, focusUp, focusDown
    case moveLeft, moveRight, moveUp, moveDown
    case workspace(Int)
    case moveToWorkspace(Int)
    case nextWorkspace, previousWorkspace
    case reload
    case quit
}

// Represents a single keybind with a keyCode and required modifiers.
struct Keybind {
    let keyCode: Int
    let modifiers: CGEventFlags
}

class HotkeyManager {
    
    static let shared = HotkeyManager()
    private var eventTap: CFMachPort?

    // All supported keybindings mapped to actions.
    // These are low-level hardware keyCodes, not characters.
    private var bindings: [(Keybind, WindowAction)] = [
        
        // --- RELOAD (Opt + Shift + R) ---
        (Keybind(keyCode: 15, modifiers: [.maskAlternate, .maskShift]), .reload),
        
        // --- QUIT (Opt + Shift + Q) ---
        (Keybind(keyCode: 12, modifiers: [.maskAlternate, .maskShift]), .quit),
        
        // --- MOVE WINDOW (Opt + Shift + H J K L) ---
        (Keybind(keyCode:  4, modifiers: [.maskAlternate, .maskShift]), .moveLeft),  // H
        (Keybind(keyCode: 37, modifiers: [.maskAlternate, .maskShift]), .moveRight), // L
        (Keybind(keyCode: 40, modifiers: [.maskAlternate, .maskShift]), .moveUp),    // K
        (Keybind(keyCode: 38, modifiers: [.maskAlternate, .maskShift]), .moveDown),  // J
        
        // --- SWITCH WORKSPACE (Opt + 1–4) ---
        (Keybind(keyCode: 18, modifiers: .maskAlternate), .workspace(1)),
        (Keybind(keyCode: 19, modifiers: .maskAlternate), .workspace(2)),
        (Keybind(keyCode: 20, modifiers: .maskAlternate), .workspace(3)),
        (Keybind(keyCode: 21, modifiers: .maskAlternate), .workspace(4)),
        
        // --- MOVE WINDOW TO WORKSPACE (Opt + Shift + 1–4) ---
        (Keybind(keyCode: 18, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(1)),
        (Keybind(keyCode: 19, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(2)),
        (Keybind(keyCode: 20, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(3)),
        (Keybind(keyCode: 21, modifiers: [.maskAlternate, .maskShift]), .moveToWorkspace(4)),
        
        // --- NEXT / PREVIOUS WORKSPACE (Opt + N / P) ---
        (Keybind(keyCode: 45, modifiers: .maskAlternate), .nextWorkspace),     // N
        (Keybind(keyCode: 35, modifiers: .maskAlternate), .previousWorkspace), // P
    ]
    
    // Installs a CGEvent tap to listen for global keyDown events.
    func startListening() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                return HotkeyManager.shared.handle(event: event)
            },
            userInfo: nil
        )
        
        // Install into current runloop
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), source, .commonModes)
        }
    }
    
    // Removes the global event tap.
    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
    
    // Main callback that runs whenever a key is pressed.
    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        
        // Ignore autorepeat to prevent repeated actions from holding keys down.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }
        
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Compare incoming event against all configured bindings.
        for (bind, action) in bindings {
            if bind.keyCode == keyCode {
                
                // Check that required modifiers match (Shift logic handled below)
                if flags.contains(bind.modifiers) {
                    
                    // Ensure shift is not mismatched between binding and event.
                    let bindingHasShift = bind.modifiers.contains(.maskShift)
                    let eventHasShift = flags.contains(.maskShift)
                    
                    if bindingHasShift == eventHasShift {
                        print("Hotkey Action Triggered → \(action)")
                        execute(action)
                        return nil // Consume the event
                    }
                }
            }
        }
        
        // If unhandled, pass event through to macOS
        return Unmanaged.passUnretained(event)
    }
    
    // Executes the window or workspace action associated with a keybind.
    private func execute(_ action: WindowAction) {
        switch action {
            
        case .reload:
            print("Refreshing layout…")
            LayoutEngine.shared.applyLayout()
            
        case .quit:
            print("Quitting HyperMac…")
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
            print("Focus movement pending implementation.")
        }
    }
}
