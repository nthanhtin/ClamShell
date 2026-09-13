import AppKit
import ScreenCaptureKit

@main
@MainActor
struct ControllerChecks {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suiteName = "dev.clamshell.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FoldController(defaults: defaults)
        let motion = controller.motion
        var previous = 0.0
        for frame in 0...60 {
            let value = motion.value(target: 1.0, time: Double(frame) / 120)
            assert(value >= previous && value <= 1, "Lid motion must settle without bouncing")
            previous = value
        }
        assert(motion.value(target: 1.0, time: 0.07) > 0.9, "Smoothing must remain responsive")
        var value = 60.0
        var velocity = 0.0
        var minimum = 61.0
        var maximum = 60.0
        for frame in 0..<240 {
            let target = (frame / 4).isMultiple(of: 2) ? 60.0 : 61.0
            motion.update(value: &value, velocity: &velocity, target: target, deltaTime: 1.0 / 120)
            if frame >= 120 {
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
        }
        assert(maximum - minimum < 0.6, "Whole-degree sensor chatter must be attenuated")
        print("Motion checks passed: no bounce, responsive settling, reduced sensor chatter")
        if controller.angle != nil {
            controller.updateAngle(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            assert(controller.angle != nil, "The display link must deliver sensor updates")
            print("Display-synchronized sensor callback passed")
        }
        // GitHub runners have virtual displays; these overlay checks need a MacBook screen.
        guard NSScreen.screens.contains(where: { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return false
            }
            return CGDisplayIsBuiltin(id) != 0
        }) else {
            print("Skipping desktop controller checks: no built-in display")
            return
        }
        controller.effect = .nativeBlur
        controller.enabled = true
        let open = controller.startAngle + 5
        let half = (controller.startAngle + controller.endAngle) / 2
        let visibleOverlays = {
            app.windows.filter { $0.identifier?.rawValue == "ClamShellOverlay" && $0.isVisible }
        }

        // Exercise the same sensor-update path without capturing any screen content.
        for degrees in [open, half, controller.endAngle, half, open] {
            controller.updateAngle(degrees)
            let expected = FoldMath.progress(angle: degrees, start: controller.startAngle, end: controller.endAngle)
            assert(controller.desktopProgress == expected)
            assert(visibleOverlays().count == (expected > 0 ? 1 : 0))
        }
        controller.updateAngle(half)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        assert(controller.angle == nil, "Sleep must stop the display link")
        assert(visibleOverlays().isEmpty, "Sleep must not leave a desktop overlay visible")
        controller.updateAngle(half)
        controller.updateAngle(nil)
        assert(visibleOverlays().isEmpty, "Sensor loss must remove the overlay")
        controller.updateAngle(half)
        controller.toggleDesktop()
        assert(!controller.enabled && visibleOverlays().isEmpty)
        print("Native mode: close, reopen, sleep, sensor loss, and pause checks passed")

        controller.enabled = true
        controller.updateAngle(nil)
        let timeoutStart = controller.startAngle
        controller.startAngle = 120
        controller.updateAngle(120, at: 0)
        controller.updateAngle(90, at: 1)
        controller.updateAngle(90, at: 1.49)
        assert(visibleOverlays().count == 1, "Keep the effect until the idle timeout")
        let heldProgress = controller.desktopProgress
        controller.updateAngle(91, at: 1.5)
        assert(controller.isSnappingBack && visibleOverlays().count == 1 && controller.desktopProgress == heldProgress,
               "The timeout must start a visible return instead of removing the overlay")
        for frame in 1..<30 {
            let previous = controller.desktopProgress
            controller.updateAngle(90, at: 1.5 + Double(frame) / 120)
            assert(controller.desktopProgress > 0 && controller.desktopProgress < previous)
            assert(visibleOverlays().count == 1, "Retain the overlay until snap-back finishes")
        }
        controller.updateAngle(90, at: 1.75)
        assert(controller.enabled && controller.desktopProgress == 0 && visibleOverlays().isEmpty,
               "Snap-back must finish on the normal desktop despite one-degree chatter")
        assert(!controller.isSnappingBack)
        controller.updateAngle(90, at: 2)
        controller.updateAngle(91, at: 3)
        assert(visibleOverlays().isEmpty, "Stationary samples must not recreate the overlay")
        controller.updateAngle(88, at: 4)
        assert(visibleOverlays().count == 1, "Closing again must resume the effect")
        controller.updateAngle(92, at: 4.4)
        controller.updateAngle(92, at: 4.8)
        assert(visibleOverlays().count == 1, "Opening movement must renew the timeout too")
        controller.updateAngle(92, at: 5)
        controller.updateAngle(92, at: 5.1)
        let returningOverlay = visibleOverlays().first
        controller.updateAngle(96, at: 5.15)
        assert(!controller.isSnappingBack && visibleOverlays().first === returningOverlay,
               "New movement must interrupt snap-back without replacing the current overlay")
        controller.updateAngle(96, at: 5.3)
        assert(visibleOverlays().count == 1, "An interrupted return must not later hide an active effect")
        controller.updateAngle(96, at: 5.7)
        assert(controller.isSnappingBack)
        controller.toggleDesktop()
        assert(!controller.isSnappingBack && visibleOverlays().isEmpty, "Pause must cancel an in-flight return")
        controller.startAngle = timeoutStart
        print("Idle snap-back checks passed: smooth return, chatter, cleanup, interruption, and pause")

        controller.idleTimeout = 1
        controller.movementThreshold = 4
        controller.smoothing = 0.20
        let restored = FoldController(defaults: defaults)
        assert(!restored.enabled, "A paused animation must stay paused after relaunch")
        assert(restored.idleTimeout == 1 && restored.movementThreshold == 4 && restored.smoothing == 0.20,
               "Animation settings must persist across controller launches")
        assert(restored.motion.value(target: 1.0, time: 0.07) < motion.value(target: 1.0, time: 0.07),
               "Higher smoothing must change the actual spring response")
        controller.startAngle = 120
        controller.enabled = true
        controller.updateAngle(nil)
        controller.updateAngle(90, at: 10)
        controller.updateAngle(90, at: 10.75)
        assert(visibleOverlays().count == 1, "The configured one-second timeout must be used")
        controller.updateAngle(90, at: 11)
        assert(controller.isSnappingBack)
        controller.updateAngle(90, at: 11.25)
        assert(visibleOverlays().isEmpty)
        controller.updateAngle(93, at: 11.3)
        assert(visibleOverlays().isEmpty, "Movement below the configured threshold must stay idle")
        controller.updateAngle(94, at: 11.4)
        assert(visibleOverlays().count == 1)
        controller.idleTimeout = 0
        controller.updateAngle(94, at: 100)
        assert(visibleOverlays().count == 1, "Off must disable idle cancellation")
        assert(!controller.isSnappingBack)
        controller.toggleDesktop()
        defaults.set(-1.0, forKey: "idleTimeout")
        defaults.set(9.0, forKey: "movementThreshold")
        defaults.set(Double.infinity, forKey: "smoothing")
        let invalid = FoldController(defaults: defaults)
        assert(invalid.idleTimeout == 0.5 && invalid.movementThreshold == 2 && invalid.smoothing == 0.10,
               "Invalid saved settings must fall back to safe defaults")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        print("Settings checks passed: persistence, custom timeout, threshold, smoothing, Off, and invalid values")

        defaults.set(true, forKey: "desktopAnimationEnabled")
        defaults.set(45.0, forKey: "startAngle")
        let autoStarted = FoldController(defaults: defaults)
        assert(autoStarted.effect == .nativeBlur && autoStarted.enabled,
               "Launching must restore the saved effect and enabled state")
        autoStarted.toggleDesktop()
        let paused = FoldController(defaults: defaults)
        assert(!paused.enabled, "Pausing must persist for the next login")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        print("Launch restoration checks passed: enabled and paused states")

        let denied = NSError(domain: SCStreamError.errorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        controller.handleCaptureError(denied)
        assert(controller.needsCaptureHelp && !controller.enabled)
        controller.handleCaptureError(NSError(domain: "ClamShellTests", code: 1))
        assert(!controller.needsCaptureHelp, "Non-permission errors must not ask for permission")
        print("Capture permission error checks passed")
    }
}
