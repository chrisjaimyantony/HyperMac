//
//  WindowAnimator.swift
//  HyperMac
//
//  Created by Chris on 27/11/25.
//  FINAL POLISH: 'EaseOutExpo' (Fast Snap, No Overlap)
//

import Cocoa
import CoreVideo

struct ActiveAnimation {
    let startFrame: CGRect
    let targetFrame: CGRect
    let startTime: CFTimeInterval
    let duration: CFTimeInterval
}

class WindowAnimator {
    static let shared = WindowAnimator()
    
    private var displayLink: CVDisplayLink?
    private var animations: [AXUIElement: ActiveAnimation] = [:]
    private var isRunning = false
    
    // Background queue
    private let axQueue = DispatchQueue(label: "com.hypermac.ax", qos: .userInteractive)
    
   
    private let animationDuration: CFTimeInterval = 0.25
    
    private var lastUpdateTimestamp: CFTimeInterval = 0
    private let minFrameDuration: CFTimeInterval = 0.016

    init() {
        var linkRef: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&linkRef)
        if let link = linkRef {
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, _ in
                WindowAnimator.shared.updateFrame()
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(link, callback, nil)
            self.displayLink = link
        }
    }
    
    func animate(window: AXUIElement, to targetRect: CGRect) {
        DispatchQueue.main.async {
            // Dirty Check
            if let current = self.animations[window]?.targetFrame, current == targetRect { return }
            
            let startRect = self.getCurrentFrame(window) ?? targetRect
            
            // Micro-movement optimization (<1px ignore)
            if abs(startRect.origin.x - targetRect.origin.x) < 1.0 &&
               abs(startRect.origin.y - targetRect.origin.y) < 1.0 &&
               abs(startRect.width - targetRect.width) < 1.0 &&
               abs(startRect.height - targetRect.height) < 1.0 {
                self.applyRaw(window: window, frame: targetRect)
                return
            }
            
            self.animations[window] = ActiveAnimation(
                startFrame: startRect,
                targetFrame: targetRect,
                startTime: CACurrentMediaTime(),
                duration: self.animationDuration
            )
            
            self.startLoop()
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
    
    private func updateFrame() {
        DispatchQueue.main.async {
            let now = CACurrentMediaTime()
            
            // 60FPS Cap
            if (now - self.lastUpdateTimestamp) < self.minFrameDuration { return }
            self.lastUpdateTimestamp = now
            
            if self.animations.isEmpty {
                self.stopLoop()
                return
            }
            
            for (window, anim) in self.animations {
                let elapsed = now - anim.startTime
                let progress = elapsed / anim.duration
                
                if progress >= 1.0 {
                    self.applyRaw(window: window, frame: anim.targetFrame)
                    self.animations.removeValue(forKey: window)
                    continue
                }
                
               
                // Formula: t == 1 ? 1 : 1 - pow(2, -10 * t)
                let t = progress
                let ease = (t == 1.0) ? 1.0 : 1.0 - pow(2.0, -10.0 * t)
                
                let currentFrame = CGRect(
                    x: self.lerp(start: anim.startFrame.minX, end: anim.targetFrame.minX, t: ease),
                    y: self.lerp(start: anim.startFrame.minY, end: anim.targetFrame.minY, t: ease),
                    width: self.lerp(start: anim.startFrame.width, end: anim.targetFrame.width, t: ease),
                    height: self.lerp(start: anim.startFrame.height, end: anim.targetFrame.height, t: ease)
                )
                
                self.applyRaw(window: window, frame: currentFrame)
            }
        }
    }
    
    private func applyRaw(window: AXUIElement, frame: CGRect) {
        axQueue.async {
            var newPos = CGPoint(x: frame.minX, y: frame.minY)
            var newSize = CGSize(width: frame.width, height: frame.height)
            
            guard let posVal = AXValueCreate(.cgPoint, &newPos),
                  let sizeVal = AXValueCreate(.cgSize, &newSize) else { return }
           AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
    }
    
    private func lerp(start: CGFloat, end: CGFloat, t: Double) -> CGFloat {
        return start + (end - start) * CGFloat(t)
    }
    
    private func getCurrentFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        return (pos == .zero && size == .zero) ? nil : CGRect(origin: pos, size: size)
    }
}
