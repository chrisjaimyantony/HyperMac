//
//  WindowAnimator.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL: "Speed Demon" (0.18s Quintic Snap)
//  If we can't be 120Hz smooth, be fast enough that nobody notices.
//

import Cocoa
import CoreVideo
import ApplicationServices

struct AnimationJob {
    let startFrame: CGRect
    let targetFrame: CGRect
    let startTime: CFTimeInterval
    let duration: CFTimeInterval
}

final class WindowAnimator {
    static let shared = WindowAnimator()
    
    private var displayLink: CVDisplayLink?
    private var animations: [AXUIElement: AnimationJob] = [:]
    private var lastAppliedFrames: [AXUIElement: CGRect] = [:]
    private var isRunning = false
    private let axQueue = DispatchQueue(label: "com.hypermac.ax", qos: .userInteractive)
    
    // 🔧 TUNING: SPEED DEMON
    // 0.18s is fast enough to hide frame drops, but slow enough to feel "animated".
    private let animationDuration: CFTimeInterval = 0.18
    
    private var suppressionDeadline: TimeInterval = 0
    
    init() {
        var linkRef: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&linkRef)
        if let link = linkRef {
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
    
    func suppressAnimations(duration: TimeInterval) {
        self.suppressionDeadline = Date().timeIntervalSince1970 + duration
    }
    
    func animate(window: AXUIElement, to targetRect: CGRect) {
        DispatchQueue.main.async {
            if Date().timeIntervalSince1970 < self.suppressionDeadline {
                self.forceIntoPlace(window: window, to: targetRect)
                return
            }
            
            if let currentJob = self.animations[window], currentJob.targetFrame == targetRect {
                return
            }
            
            let startRect = self.getCurrentFrame(window) ?? targetRect
            
            // < 1px optimization
            if abs(startRect.origin.x - targetRect.origin.x) < 1.0 &&
               abs(startRect.origin.y - targetRect.origin.y) < 1.0 &&
               abs(startRect.width - targetRect.width) < 1.0 &&
               abs(startRect.height - targetRect.height) < 1.0 {
                self.forceIntoPlace(window: window, to: targetRect)
                return
            }
            
            self.animations[window] = AnimationJob(
                startFrame: startRect,
                targetFrame: targetRect,
                startTime: CACurrentMediaTime(),
                duration: self.animationDuration
            )
            
            self.startLoop()
        }
    }
    
    func forceIntoPlace(window: AXUIElement, to targetRect: CGRect) {
        DispatchQueue.main.async {
            self.animations.removeValue(forKey: window)
            self.lastAppliedFrames.removeValue(forKey: window)
        }
        axQueue.async {
            self.applyRaw(window: window, frame: targetRect)
            usleep(10000)
            self.applyRaw(window: window, frame: targetRect)
        }
    }
    
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
    
    func updateFrame() {
        DispatchQueue.main.async {
            if self.animations.isEmpty {
                self.stopLoop()
                return
            }
            
            let now = CACurrentMediaTime()
            var finished: [AXUIElement] = []
            
            for (window, job) in self.animations {
                
                let elapsed = now - job.startTime
                var progress = elapsed / job.duration
                
                if progress >= 1.0 {
                    progress = 1.0
                    finished.append(window)
                }
                
                // 🔥 CURVE: EaseOutQuint (Power of 5)
                // Starts EXPLOSIVELY fast, then brakes hard.
                // This hides lag because the window covers 80% of the distance in the first 3 frames.
                let t = progress
                let ease = 1.0 - pow(1.0 - t, 5.0)
                
                let currentFrame = CGRect(
                    x: self.lerp(job.startFrame.minX, job.targetFrame.minX, ease),
                    y: self.lerp(job.startFrame.minY, job.targetFrame.minY, ease),
                    width: self.lerp(job.startFrame.width, job.targetFrame.width, ease),
                    height: self.lerp(job.startFrame.height, job.targetFrame.height, ease)
                )
                
                // Integer Snap
                let finalFrame = CGRect(
                    x: round(currentFrame.minX),
                    y: round(currentFrame.minY),
                    width: round(currentFrame.width),
                    height: round(currentFrame.height)
                )
                
                if let last = self.lastAppliedFrames[window], last == finalFrame {
                    continue
                }
                
                self.lastAppliedFrames[window] = finalFrame
                
                self.axQueue.async {
                    self.applyRaw(window: window, frame: finalFrame)
                }
            }
            
            for win in finished {
                self.animations.removeValue(forKey: win)
                if let job = self.animations[win] {
                   self.axQueue.async { self.applyRaw(window: win, frame: job.targetFrame) }
                }
            }
        }
    }
    
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
        if let p = pRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        if pos == .zero && size == .zero { return nil }
        return CGRect(origin: pos, size: size)
    }
}
