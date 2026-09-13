import AppKit
import QuartzCore
import ScreenCaptureKit
import ServiceManagement
import SwiftUI

struct FoldSurface: View, @MainActor Animatable {
    var progress: Double
    var image: NSImage?
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    SampleScene().drawingGroup()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .layerEffect(ShaderLibrary.foldGlass(.float2(geometry.size), .float(progress)),
                         maxSampleOffset: CGSize(width: geometry.size.width * 0.25, height: geometry.size.height))
        }
        .accessibilityLabel("Fold animation preview")
        .accessibilityValue("\(Int(progress * 100)) percent closed")
    }
}

struct SampleScene: View {
    var showsTitle = true

    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Color(red: 0.87, green: 0.83, blue: 0.73), .black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(0..<4) { index in
                    let shift = CGFloat(index) * 0.18
                    Path { path in
                        path.move(to: CGPoint(x: g.size.width * (0.1 + shift), y: 0))
                        path.addCurve(to: CGPoint(x: g.size.width * (0.3 + shift), y: g.size.height),
                                      control1: CGPoint(x: g.size.width * (0.8 + shift), y: g.size.height * 0.42),
                                      control2: CGPoint(x: -g.size.width * 0.2, y: g.size.height * 0.7))
                        path.addLine(to: CGPoint(x: g.size.width * 1.6, y: g.size.height))
                        path.addLine(to: CGPoint(x: g.size.width * 1.6, y: 0))
                    }
                    .fill(LinearGradient(colors: [Color(white: 0.96 - Double(index) * 0.13),
                                                   Color(white: 0.3 - Double(index) * 0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.55), radius: 22, x: -12, y: 8)
                }
                if showsTitle {
                    VStack(spacing: 6) {
                        Text("ClamShell").font(.system(size: 44, weight: .light, design: .rounded))
                        Text("A little motion. A different perspective.").font(.callout)
                    }
                    .foregroundStyle(.white).shadow(radius: 15)
                }
            }
        }
    }
}

@MainActor
final class FoldController: NSObject, ObservableObject {
    enum Effect: String, CaseIterable, Identifiable {
        case fold = "Perspective fold"
        case nativeBlur = "Native blur · no capture"
        var id: Self { self }
    }

    @Published var effect = Effect.fold {
        didSet {
            defaults.set(effect.rawValue, forKey: "effect")
            enabled = false
            needsCaptureHelp = false
            resetOverlay()
            status = effect == .nativeBlur
                ? "Live system blur and dimming. No Screen Recording permission needed."
                : "Perspective folding uses a desktop screenshot."
        }
    }
    @Published var angle: Double?
    @Published var manualAngle = 90.0
    @Published var followsLid = false
    @Published var enabled = false {
        didSet { defaults.set(enabled, forKey: "desktopAnimationEnabled") }
    }
    @Published var needsCaptureHelp = false
    @Published var startAngle = 85.0 {
        didSet { defaults.set(startAngle, forKey: "startAngle") }
    }
    @Published var endAngle = 5.0 {
        didSet { defaults.set(endAngle, forKey: "endAngle") }
    }
    @Published var idleTimeout = 0.5 {
        didSet { defaults.set(idleTimeout, forKey: "idleTimeout") }
    }
    @Published var movementThreshold = 2.0 {
        didSet { defaults.set(movementThreshold, forKey: "movementThreshold") }
    }
    @Published var smoothing = 0.10 {
        didSet { defaults.set(smoothing, forKey: "smoothing") }
    }
    @Published var desktopProgress = 0.0
    @Published var status = "Preview is ready. Drag the angle slider or follow your lid."
    private var sensor: LidSensor?
    private var displayLink: CADisplayLink?
    private var overlay: NSWindow?
    private var nativeBlur: NSVisualEffectView?
    private var nativeShade: NSView?
    private var captureFilter: SCContentFilter?
    private var captureTask: Task<Void, Never>?
    private var preparingCapture = false
    private var captureGeneration = 0
    private var failedCapture = false
    private var motionAngle: Double?
    private var lastMotionTime: TimeInterval = 0
    private var snapBackStart: (time: TimeInterval, progress: Double)?
    private let defaults: UserDefaults

    var isSnappingBack: Bool { snapBackStart != nil }
    // Retarget smoothly across whole-degree sensor steps, without bounce.
    var motion: Spring { Spring(response: smoothing, dampingRatio: 1) }

    var previewProgress: Double {
        FoldMath.progress(angle: followsLid ? (angle ?? startAngle) : manualAngle,
                          start: startAngle, end: endAngle)
    }

    init(defaults: UserDefaults = .standard) {
        let restoreAnimation = defaults.bool(forKey: "desktopAnimationEnabled")
        self.defaults = defaults
        super.init()
        effect = Effect(rawValue: defaults.string(forKey: "effect") ?? "") ?? .fold
        let savedStart = defaults.object(forKey: "startAngle") as? Double ?? 85
        let savedEnd = defaults.object(forKey: "endAngle") as? Double ?? 5
        if savedStart.isFinite, savedEnd.isFinite, (45...130).contains(savedStart),
           (0...30).contains(savedEnd) {
            startAngle = savedStart
            endAngle = savedEnd
        }
        let savedTimeout = defaults.object(forKey: "idleTimeout") as? Double ?? 0.5
        if savedTimeout.isFinite, (0...3).contains(savedTimeout) { idleTimeout = savedTimeout }
        let savedThreshold = defaults.object(forKey: "movementThreshold") as? Double ?? 2
        if savedThreshold.isFinite, (1...5).contains(savedThreshold) { movementThreshold = savedThreshold }
        let savedSmoothing = defaults.object(forKey: "smoothing") as? Double ?? 0.10
        if savedSmoothing.isFinite, (0.05...0.30).contains(savedSmoothing) { smoothing = savedSmoothing }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if restoreAnimation {
            enabled = true
            status = "Desktop animation restored. Move your lid to begin."
        }
        resume()
    }

    @objc private func resume() {
        displayLink?.invalidate()
        displayLink = nil
        sensor = LidSensor()
        tick()
        if enabled, effect == .fold, captureFilter == nil, captureTask == nil {
            captureDesktop(prepareOnly: true)
        }
        if let screen = builtInScreen ?? NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(tick))
            let maximum = Float(screen.maximumFramesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum),
                                                           maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    @objc private func suspend() {
        displayLink?.invalidate()
        displayLink = nil
        sensor = nil
        angle = nil
        motionAngle = nil
        captureFilter = nil
        resetOverlay()
    }

    @objc private func tick() {
        updateAngle(sensor?.readAngle())
    }

    func updateAngle(_ reading: Double?, at time: TimeInterval = CACurrentMediaTime()) {
        if angle != reading { angle = reading }
        guard enabled, let reading else {
            motionAngle = nil
            if overlay != nil || captureTask != nil { resetOverlay() }
            return
        }
        if let reference = motionAngle, abs(reading - reference) < movementThreshold {
            // Ignore sensor chatter, and stay idle until the lid moves again.
            if idleTimeout > 0, time - lastMotionTime >= idleTimeout {
                snapBack(at: time)
                return
            }
        } else {
            motionAngle = reading
            lastMotionTime = time
        }
        snapBackStart = nil
        let progress = FoldMath.progress(angle: reading, start: startAngle, end: endAngle)
        if progress == 0 {
            failedCapture = false
            if overlay != nil || (captureTask != nil && !preparingCapture) { resetOverlay() }
        } else if effect == .nativeBlur {
            if overlay == nil { showNativeBlur() }
        } else if overlay == nil, captureTask == nil, !failedCapture {
            captureDesktop()
        }
        applyProgress(progress)
    }

    private func applyProgress(_ progress: Double) {
        if abs(desktopProgress - progress) > 0.0001 { desktopProgress = progress }
        nativeBlur?.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0 : min(1, progress * 2)
        nativeShade?.alphaValue = progress * progress
    }

    private func snapBack(at time: TimeInterval) {
        guard overlay != nil else {
            if captureTask != nil || desktopProgress > 0 { resetOverlay() }
            return
        }
        let start = snapBackStart ?? (time: time, progress: desktopProgress)
        snapBackStart = start
        let fraction = min(1, max(0, (time - start.time) / 0.25))
        if fraction == 1 {
            resetOverlay()
        } else {
            applyProgress(start.progress * (1 - UnitCurve.easeOut.value(at: fraction)))
        }
    }

    func toggleDesktop() {
        if enabled {
            enabled = false
            resetOverlay()
            status = "Desktop animation paused."
            return
        }
        guard angle != nil else {
            status = "No readable lid-angle sensor. The manual preview still works."
            return
        }
        needsCaptureHelp = false
        enabled = true
        failedCapture = false
        motionAngle = nil
        status = "Ready. Close or open through the selected angle range while your desktop is unlocked."
        if effect == .fold { captureDesktop(prepareOnly: true) }
        tick()
    }

    func reopen() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error { self?.status = "Could not reopen ClamShell: \(error.localizedDescription)" }
                else { NSApp.terminate(nil) }
            }
        }
    }

    func handleCaptureError(_ error: Error) {
        failedCapture = true
        captureFilter = nil
        needsCaptureHelp = (error as? SCStreamError)?.code == .userDeclined
        status = needsCaptureHelp
            ? "macOS hasn't granted this running copy access. If ClamShell is already allowed, reopen it. Otherwise, enable it in Screen Recording settings."
            : "Screen capture failed: \(error.localizedDescription)"
        enabled = false
        resetOverlay()
    }

    @objc private func resetOverlay() {
        snapBackStart = nil
        captureGeneration += 1
        captureTask?.cancel()
        captureTask = nil
        preparingCapture = false
        overlay?.orderOut(nil)
        overlay = nil
        nativeBlur = nil
        nativeShade = nil
        desktopProgress = 0
    }

    @objc private func displayChanged() {
        captureFilter = nil
        resetOverlay()
        if displayLink != nil { resume() }
    }

    private var builtInScreen: NSScreen? {
        NSScreen.screens.first(where: {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        })
    }

    private func makeOverlay(on screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("ClamShellOverlay")
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        overlay = window
        return window
    }

    private func showNativeBlur() {
        guard let screen = builtInScreen else { return }
        let window = makeOverlay(on: screen)
        let content = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        let blur = NSVisualEffectView(frame: content.bounds)
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.alphaValue = 0
        let shade = NSView(frame: content.bounds)
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor.black.cgColor
        shade.alphaValue = 0
        content.addSubview(blur)
        content.addSubview(shade)
        window.contentView = content
        nativeBlur = blur
        nativeShade = shade
        window.orderFrontRegardless()
    }

    private func captureDesktop(prepareOnly: Bool = false) {
        guard let screen = builtInScreen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            failedCapture = true
            status = "The built-in display is unavailable."
            return
        }
        let generation = captureGeneration
        preparingCapture = prepareOnly
        captureTask = Task { [weak self] in
            guard let self, !Task.isCancelled, generation == self.captureGeneration else { return }
            defer {
                if generation == captureGeneration {
                    captureTask = nil
                    preparingCapture = false
                }
            }
            do {
                if captureFilter == nil {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    guard !Task.isCancelled, generation == captureGeneration else { return }
                    guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                        failedCapture = true
                        status = "The built-in display is unavailable for capture."
                        return
                    }
                    let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                    captureFilter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                }
                guard !prepareOnly, !Task.isCancelled, let filter = captureFilter else { return }
                let config = SCStreamConfiguration()
                config.width = CGDisplayPixelsWide(displayID)
                config.height = CGDisplayPixelsHigh(displayID)
                config.showsCursor = true
                let screenshot = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard !Task.isCancelled, generation == captureGeneration, enabled, desktopProgress > 0 else { return }
                let window = makeOverlay(on: screen)
                window.backgroundColor = .black
                window.contentView = NSHostingView(rootView: DesktopSurface(controller: self,
                    image: NSImage(cgImage: screenshot, size: screen.frame.size)))
                window.orderFrontRegardless()
                captureTask = nil
            } catch {
                guard generation == captureGeneration else { return }
                handleCaptureError(error)
            }
        }
    }
}

private struct DesktopSurface: View {
    @ObservedObject var controller: FoldController
    let image: NSImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        FoldSurface(progress: reduceMotion ? 0 : controller.desktopProgress, image: image)
            .opacity(reduceMotion ? 1 - controller.desktopProgress : 1)
            .background(.black)
            // Snap-back is already sampled on the display link; don't smooth it twice.
            .animation(controller.isSnappingBack ? nil : .interpolatingSpring(controller.motion),
                       value: controller.desktopProgress)
    }
}

private struct ControlPanel: View {
    @ObservedObject var controller: FoldController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change Start at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ClamShell").font(.largeTitle.weight(.semibold))
                    Text("The fold follows you.").foregroundStyle(.secondary)
                }
                Spacer()
                Label(controller.angle.map { "\(Int($0))°" } ?? "No sensor", systemImage: "laptopcomputer")
                    .font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
            FoldSurface(progress: reduceMotion || controller.effect == .nativeBlur ? 0 : controller.previewProgress)
                .blur(radius: !reduceMotion && controller.effect == .nativeBlur ? controller.previewProgress * 12 : 0)
                .opacity(reduceMotion || controller.effect == .nativeBlur ? 1 - controller.previewProgress : 1)
                .background(.black)
                .frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityValue("\(Int(controller.previewProgress * 100)) percent closed")
                .animation(.interpolatingSpring(controller.motion), value: controller.previewProgress)
            HStack {
                Text("Preview angle").fontWeight(.medium)
                Spacer()
                Toggle("Follow my lid", isOn: $controller.followsLid)
                    .disabled(controller.angle == nil).toggleStyle(.switch)
            }
            HStack {
                Image(systemName: "laptopcomputer.trianglebadge.exclamationmark")
                Slider(value: $controller.manualAngle, in: 0...140)
                    .accessibilityLabel("Preview lid angle").disabled(controller.followsLid)
                Text("\(Int(controller.followsLid ? (controller.angle ?? 0) : controller.manualAngle))°")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
            }
            Divider()
            HStack {
                Picker("Desktop effect", selection: $controller.effect) {
                    ForEach(FoldController.Effect.allCases) { effect in
                        Text(effect == .nativeBlur ? "Native blur" : effect.rawValue).tag(effect)
                    }
                }
                SettingsLink { Text("Animation settings…") }
            }
            HStack {
                Text("Start folding at")
                Slider(value: $controller.startAngle, in: 45...130, step: 1)
                    .accessibilityLabel("Start folding angle")
                Text("\(Int(controller.startAngle))°").monospacedDigit().frame(width: 42)
            }
            HStack {
                Text("Fully dark at").frame(width: 94, alignment: .leading)
                Slider(value: $controller.endAngle, in: 0...30, step: 1)
                    .accessibilityLabel("Fully closed angle")
                Text("\(Int(controller.endAngle))°").monospacedDigit().frame(width: 42)
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Start at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { setStartAtLogin($0) }
                )).toggleStyle(.switch)
                if loginStatus == .requiresApproval {
                    Text("Allow ClamShell in macOS Login Items to finish enabling it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                Text(controller.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Button(controller.enabled ? "Pause desktop animation" : "Enable desktop animation") {
                    controller.toggleDesktop()
                }.buttonStyle(.borderedProminent)
            }
            if controller.needsCaptureHelp {
                HStack {
                    Link("Open Screen Recording Settings", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    Spacer()
                    Button("Reopen ClamShell") { controller.reopen() }
                }
            }
        }
        .padding(28).frame(width: 660)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .enabled { loginError = nil }
        }
    }
}

private struct AnimationSettings: View {
    @ObservedObject var controller: FoldController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Animation settings").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Idle timeout").frame(width: 150, alignment: .leading)
                    Slider(value: $controller.idleTimeout, in: 0...3, step: 0.1)
                        .accessibilityLabel("Idle timeout")
                    Text(controller.idleTimeout == 0 ? "Off" : String(format: "%.1f s", controller.idleTimeout))
                        .monospacedDigit().frame(width: 58, alignment: .trailing)
                }
                Text("Snap back after the lid stays still. Set to Off to keep the effect visible.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Movement threshold").frame(width: 150, alignment: .leading)
                    Slider(value: $controller.movementThreshold, in: 1...5, step: 1)
                        .accessibilityLabel("Movement threshold")
                    Text("\(Int(controller.movementThreshold))°")
                        .monospacedDigit().frame(width: 58, alignment: .trailing)
                }
                Text("How far the lid must move to restart the effect. Higher values ignore more jitter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Motion smoothing").frame(width: 150, alignment: .leading)
                    Slider(value: $controller.smoothing, in: 0.05...0.30, step: 0.01)
                        .accessibilityLabel("Motion smoothing")
                    Text("\(Int((controller.smoothing * 1000).rounded())) ms")
                        .monospacedDigit().frame(width: 58, alignment: .trailing)
                }
                Text("Lower values respond faster; higher values soften the fold and preview motion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24).frame(width: 530)
    }
}

#if !CONTROLLER_CHECKS && !ASSET_RENDERER
@main
#endif
struct ClamShellApp: App {
    @StateObject private var controller = FoldController()
    var body: some Scene {
        Window("ClamShell", id: "controls") { ControlPanel(controller: controller) }
            .windowResizability(.contentSize)
        Settings { AnimationSettings(controller: controller) }
        MenuBarExtra("ClamShell", systemImage: "laptopcomputer") {
            MenuContents(controller: controller)
        }
    }
}

private struct MenuContents: View {
    @ObservedObject var controller: FoldController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(controller.angle.map { "Lid angle: \(Int($0))°" } ?? "Lid sensor unavailable")
        Button("Show ClamShell") {
            openWindow(id: "controls")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(controller.enabled ? "Pause animation" : "Enable animation") { controller.toggleDesktop() }
        Divider()
        Button("Quit ClamShell") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
