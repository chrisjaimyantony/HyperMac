//
//  WindowAnimator.swift
//  HyperMac
//
//  High-performance window animation controller.
//  This class manages the smooth interpolation of window frames.
//
//  OPTIMIZATION STRATEGY: Backpressure Dropping
//  At 60Hz, the system has ~16ms to render a frame. Accessibility API calls
//  can sometimes take longer than this budget. Instead of letting the command
//  queue pile up (causing stutter), this controller detects if a window is
//  currently "busy" updating. If it is, we skip the calculation for that frame
//  and wait for the next cycle. This results in smoother visual motion.
//
//  Created by Chris on 27/11/25.
//

import Cocoa
import CoreVideo
import ApplicationServices

// Represents the state of a single window's animation.
struct AnimationJob {
    let startFrame: CGRect
    let targetFrame: CGRect
    let startTime: CFTimeInterval
    let duration: CFTimeInterval
}

final class WindowAnimator {
    static let shared = WindowAnimator()
    
    // The display link responsible for timing the animation loop with the screen refresh rate.
    private var displayLink: CVDisplayLink?
    
    // We protect these variables with a dedicated queue to ensure thread safety.
    private var animations: [AXUIElement: AnimationJob] = [:]
    private var lastAppliedFrames: [AXUIElement: CGRect] = [:]
    
    private var isRunning = false
    private var suppressionDeadline: TimeInterval = 0
    
    // MARK: - Threading Architecture
    
    // 1. Logic Queue:
    // This serial queue handles all mathematical calculations (lerping, easing).
    // It runs at 'UserInteractive' priority to ensure animations start immediately.
    private let logicQueue = DispatchQueue(label: "com.hypermac.animator.logic", qos: .userInteractive)
    
    // 2. AX Queue:
    // This serial queue executes the slow Accessibility system calls.
    // By separating this from the Logic Queue, we ensure that a slow system call
    // does not block the calculation of the next frame for other windows.
    private let axQueue = DispatchQueue(label: "com.hypermac.ax", qos: .userInteractive)
    
    // MARK: - Backpressure Control
    
    // This set acts as a traffic controller. It tracks which windows are currently
    // in the process of being moved by the Operating System.
    // If a window is in this set, we skip generating new frames for it until the OS reports it is done.
    private var busyWindows: Set<AXUIElement> = []
    
    // A duration of 0.22 seconds is tuned to mask 60Hz latency without feeling sluggish.
    private let animationDuration: CFTimeInterval = 0.22
    
    // MARK: - Initialization
    
    init() {
        var linkRef: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&linkRef)
        
        if let link = linkRef {
            // Set up the callback function that runs on every vertical sync (VSync).
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, ctx in
                let animator = Unmanaged<WindowAnimator>.fromOpaque(ctx!).takeUnretainedValue()
                animator.updateFrame()
                return kCVReturnSuccess
            }
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            CVDisplayLinkSetOutputCallback(link, callback, ctx)
            self.displayLink = link
        }
    }
    
    // MARK: - Suppression Control
    
    // Temporarily disables animations for a specified duration.
    // This is typically used during space changes to prevent layout conflicts.
    func suppressAnimations(duration: TimeInterval) {
        logicQueue.async {
            self.suppressionDeadline = Date().timeIntervalSince1970 + duration
        }
    }
    
    // MARK: - Schedule Animation
    
    // Initiates a new animation for a specific window to a target rectangle.
    func animate(window: AXUIElement, to targetRect: CGRect) {
        logicQueue.async {
            
            // 1. Check if animations are currently suppressed.
            if Date().timeIntervalSince1970 < self.suppressionDeadline {
                self.forceIntoPlaceInternal(window: window, to: targetRect)
                return
            }
            
            // 2. Round the target values to the nearest integer.
            // Fractional pixels can cause the window to blur or shimmy.
            let cleanTarget = CGRect(
                x: round(targetRect.minX),
                y: round(targetRect.minY),
                width: round(targetRect.width),
                height: round(targetRect.height)
            )
            
            // 3. Optimization: Ignore requests if the window is already moving to this exact location.
            if let job = self.animations[window] {
                if abs(job.targetFrame.minX - cleanTarget.minX) < 1.0 &&
                   abs(job.targetFrame.minY - cleanTarget.minY) < 1.0 &&
                   abs(job.targetFrame.width - cleanTarget.width) < 1.0 &&
                   abs(job.targetFrame.height - cleanTarget.height) < 1.0 {
                    return
                }
            }
            
            // 4. Determine the starting position.
            // If the Accessibility API fails to return a frame, default to the target to avoid jumps.
            let startRect = self.getCurrentFrame(window) ?? cleanTarget
            
            // 5. Threshold Check: If the distance is negligible (< 2px), skip animation.
            if abs(startRect.origin.x - cleanTarget.origin.x) < 2.0 &&
               abs(startRect.origin.y - cleanTarget.origin.y) < 2.0 &&
               abs(startRect.width - cleanTarget.width) < 2.0 &&
               abs(startRect.height - cleanTarget.height) < 2.0 {
                self.forceIntoPlaceInternal(window: window, to: cleanTarget)
                return
            }
            
            // 6. Register the new animation job.
            self.animations[window] = AnimationJob(
                startFrame: startRect,
                targetFrame: cleanTarget,
                startTime: CACurrentMediaTime(),
                duration: self.animationDuration
            )
            
            // Ensure the display link loop is running.
            self.startLoop()
        }
    }
    
    // MARK: - Instant Application
    
    // Public wrapper to immediately move a window, bypassing animation.
    func forceIntoPlace(window: AXUIElement, to targetRect: CGRect) {
        logicQueue.async {
            self.forceIntoPlaceInternal(window: window, to: targetRect)
        }
    }
    
    // Internal helper that cleans up state and dispatches the raw move command.
    private func forceIntoPlaceInternal(window: AXUIElement, to targetRect: CGRect) {
        self.animations.removeValue(forKey: window)
        self.lastAppliedFrames.removeValue(forKey: window)
        
        // Important: Clear the 'busy' flag so this update is forced through immediately.
        self.busyWindows.remove(window)
        
        axQueue.async {
            self.applyRaw(window: window, frame: targetRect)
        }
    }
    
    // MARK: - DisplayLink Control
    
    private func startLoop() {
        guard !isRunning, let link = displayLink else { return }
        CVDisplayLinkStart(link)
        isRunning = true
    }
    
    private func stopLoop() {
        guard isRunning, let link = displayLink else { return }
        CVDisplayLinkStop(link)
        isRunning = false
    }
    
    // MARK: - Frame Calculation (The Core Loop)
    
    // This function runs ~60 times per second.
    func updateFrame() {
        logicQueue.async {
            
            // If no animations are active, stop the display link to save CPU.
            if self.animations.isEmpty {
                self.stopLoop()
                return
            }
            
            let now = CACurrentMediaTime()
            var finishedWindows: [AXUIElement] = []
            
            for (window, job) in self.animations {
                
                // --- BACKPRESSURE CHECK ---
                // If this specific window is still processing the PREVIOUS frame (stuck in the AXQueue),
                // we skip this update entirely.
                // We let the math continue (elapsed time still increases), but we don't spam the system.
                // We will catch up on the next frame when the system is ready.
                if self.busyWindows.contains(window) {
                    continue
                }
                
                let elapsed = now - job.startTime
                var progress = elapsed / job.duration
                
                if progress >= 1.0 {
                    progress = 1.0
                    finishedWindows.append(window)
                }
                
                // Mathematical Easing: Quartic Ease-Out
                // Formula: 1 - (1 - t)^4
                // This curve starts fast and decelerates smoothly, hiding 60Hz stutter.
                let t = progress
                let ease = 1.0 - pow(1.0 - t, 4.0)
                
                // Linear Interpolation
                let curr = CGRect(
                    x: self.lerp(job.startFrame.minX, job.targetFrame.minX, ease),
                    y: self.lerp(job.startFrame.minY, job.targetFrame.minY, ease),
                    width: self.lerp(job.startFrame.width, job.targetFrame.width, ease),
                    height: self.lerp(job.startFrame.height, job.targetFrame.height, ease)
                )
                
                // Integer Snapping
                let snapped = CGRect(
                    x: round(curr.minX),
                    y: round(curr.minY),
                    width: round(curr.width),
                    height: round(curr.height)
                )
                
                // Redundancy Check: Do not send command if the frame hasn't changed.
                if let last = self.lastAppliedFrames[window], last == snapped {
                    continue
                }
                
                self.lastAppliedFrames[window] = snapped
                
                // Mark window as busy so subsequent loops know to wait.
                self.busyWindows.insert(window)
                
                // Dispatch the slow system call to the "Muscle" queue.
                self.axQueue.async {
                    // Perform the actual move.
                    self.applyRaw(window: window, frame: snapped)
                    
                    // Once finished, callback to the Logic Queue to release the busy flag.
                    self.logicQueue.async {
                        self.busyWindows.remove(window)
                    }
                }
            }
            
            // Clean up completed animations.
            for win in finishedWindows {
                self.animations.removeValue(forKey: win)
                
                // Ensure we force the final frame even if the window was marked busy.
                self.busyWindows.remove(win)
                
                if let job = self.animations[win] {
                    self.axQueue.async {
                        self.applyRaw(window: win, frame: job.targetFrame)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    // Linearly interpolates between two values based on a fraction t.
    private func lerp(_ start: CGFloat, _ end: CGFloat, _ t: Double) -> CGFloat {
        return start + (end - start) * CGFloat(t)
    }
    
    // Executes the low-level Accessibility API calls.
    private func applyRaw(window: AXUIElement, frame: CGRect) {
        var pos = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        
        guard let p = AXValueCreate(.cgPoint, &pos),
              let s = AXValueCreate(.cgSize, &size) else { return }
        
        // CRITICAL: Update Size first, then Position.
        // If we move before resizing, the window might hit a screen edge constraint and bounce back.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
    }
    
    // Retrieves the current frame from the Accessibility API.
    private func getCurrentFrame(_ window: AXUIElement) -> CGRect? {
        var pRef: CFTypeRef?
        var sRef: CFTypeRef?
        
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sRef)
        
        var pos = CGPoint.zero
        var size = CGSize.zero
        
        if let p = pRef, CFGetTypeID(p) == AXValueGetTypeID() {
            AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        }
        if let s = sRef, CFGetTypeID(s) == AXValueGetTypeID() {
            AXValueGetValue(s as! AXValue, .cgSize, &size)
        }
        
        if pos == .zero && size == .zero { return nil }
        
        return CGRect(origin: pos, size: size)
    }
}
