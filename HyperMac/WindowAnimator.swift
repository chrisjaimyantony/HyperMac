//
//  WindowAnimator.swift
//  HyperMac
//
//  High-performance window animation controller.
//  Implements a fast 0.18s EaseOutQuint interpolation (“Speed Demon”)
//  designed to hide macOS AX frame stutter when 120Hz is not possible.
//
//  Core Responsibilities:
//  - Compute smooth animation frames via quintic easing
//  - Avoid subpixel jitter (integer rounding)
//  - Suppress animation during throws or transitions
//  - Deliver AX frame updates asynchronously on a dedicated queue
//
//  Created by Chris on 27/11/25.
//  FINAL: "Speed Demon" — fast enough that dropped frames are invisible.
//

import Cocoa
import CoreVideo
import ApplicationServices

// A scheduled animation for a single window.
struct AnimationJob {
    let startFrame: CGRect
    let targetFrame: CGRect
    let startTime: CFTimeInterval
    let duration: CFTimeInterval
}

final class WindowAnimator {
    static let shared = WindowAnimator()
    
    private var displayLink: CVDisplayLink?
    
    // Active animations mapped to each AX window element.
    private var animations: [AXUIElement: AnimationJob] = [:]
    
    // Cache of the last frame actually applied to avoid redundant AX calls.
    private var lastAppliedFrames: [AXUIElement: CGRect] = [:]
    
    private var isRunning = false
    
    // AX operations run here to avoid blocking UI.
    private let axQueue = DispatchQueue(label: "com.hypermac.ax", qos: .userInteractive)
    
    // Animation speed: tuned for speed > smoothness.
    private let animationDuration: CFTimeInterval = 0.18
    
    // When non-zero, animations are suppressed (e.g., during window throws).
    private var suppressionDeadline: TimeInterval = 0
    
    // MARK: - Init
    
    init() {
        var linkRef: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&linkRef)
        
        if let link = linkRef {
            // DisplayLink callback trampoline.
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
    
    // MARK: - Suppression
    
    func suppressAnimations(duration: TimeInterval) {
        suppressionDeadline = Date().timeIntervalSince1970 + duration
    }
    
    // MARK: - Schedule Animation
    
    func animate(window: AXUIElement, to targetRect: CGRect) {
        DispatchQueue.main.async {
            
            // If animations are temporarily disabled, snap instantly.
            if Date().timeIntervalSince1970 < self.suppressionDeadline {
                self.forceIntoPlace(window: window, to: targetRect)
                return
            }
            
            // Skip if already animating to the same target.
            if let job = self.animations[window],
               job.targetFrame == targetRect {
                return
            }
            
            let startRect = self.getCurrentFrame(window) ?? targetRect
            
            // Skip animation if movement <1px.
            if abs(startRect.origin.x - targetRect.origin.x) < 1.0 &&
               abs(startRect.origin.y - targetRect.origin.y) < 1.0 &&
               abs(startRect.width - targetRect.width) < 1.0 &&
               abs(startRect.height - targetRect.height) < 1.0 {
                self.forceIntoPlace(window: window, to: targetRect)
                return
            }
            
            // Create new animation job.
            self.animations[window] = AnimationJob(
                startFrame: startRect,
                targetFrame: targetRect,
                startTime: CACurrentMediaTime(),
                duration: self.animationDuration
            )
            
            self.startLoop()
        }
    }
    
    // MARK: - Instant Snap
    
    func forceIntoPlace(window: AXUIElement, to targetRect: CGRect) {
        DispatchQueue.main.async {
            self.animations.removeValue(forKey: window)
            self.lastAppliedFrames.removeValue(forKey: window)
        }
        
        // Apply twice to defeat AX race conditions.
        axQueue.async {
            self.applyRaw(window: window, frame: targetRect)
            usleep(10000)
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
    
    // MARK: - Animation Frame Update
    
    func updateFrame() {
        DispatchQueue.main.async {
            
            // No work → stop the loop.
            if self.animations.isEmpty {
                self.stopLoop()
                return
            }
            
            let now = CACurrentMediaTime()
            var finishedWindows: [AXUIElement] = []
            
            // Iterate through all active animations.
            for (window, job) in self.animations {
                
                let elapsed = now - job.startTime
                var progress = elapsed / job.duration
                
                if progress >= 1.0 {
                    progress = 1.0
                    finishedWindows.append(window)
                }
                
                //-----------------------------------------
                // EaseOutQuint (t → 1 - (1 - t)^5)
                // Very fast at start, sharply decelerates.
                //-----------------------------------------
                let t = progress
                let ease = 1.0 - pow(1.0 - t, 5.0)
                
                let curr = CGRect(
                    x: self.lerp(job.startFrame.minX, job.targetFrame.minX, ease),
                    y: self.lerp(job.startFrame.minY, job.targetFrame.minY, ease),
                    width: self.lerp(job.startFrame.width, job.targetFrame.width, ease),
                    height: self.lerp(job.startFrame.height, job.targetFrame.height, ease)
                )
                
                // Integer snap to prevent subpixel jitter.
                let snapped = CGRect(
                    x: round(curr.minX),
                    y: round(curr.minY),
                    width: round(curr.width),
                    height: round(curr.height)
                )
                
                // Skip redundant frame.
                if let last = self.lastAppliedFrames[window], last == snapped {
                    continue
                }
                
                self.lastAppliedFrames[window] = snapped
                
                // Apply on AX queue.
                self.axQueue.async {
                    self.applyRaw(window: window, frame: snapped)
                }
            }
            
            // Finalize completed animations.
            for win in finishedWindows {
                self.animations.removeValue(forKey: win)
                
                // Ensure perfect pixel alignment at the end.
                if let job = self.animations[win] {
                    self.axQueue.async {
                        self.applyRaw(window: win, frame: job.targetFrame)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func lerp(_ start: CGFloat, _ end: CGFloat, _ t: Double) -> CGFloat {
        return start + (end - start) * CGFloat(t)
    }
    
    private func applyRaw(window: AXUIElement, frame: CGRect) {
        var pos = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        
        guard let p = AXValueCreate(.cgPoint, &pos),
              let s = AXValueCreate(.cgSize, &size) else { return }
        
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
    }
    
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
