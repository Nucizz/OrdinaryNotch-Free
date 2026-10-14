import AppKit
import SwiftUI
import QuartzCore

@MainActor protocol LockScreenSpaceDelegating: AnyObject {
    func delegate(_ window: NSWindow) async -> Bool
    func undelegate(_ window: NSWindow)
}
extension LockScreenSpace: LockScreenSpaceDelegating {}

final class LockScreenActivityPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LockScreenActivityHostingView: NSHostingView<LockScreenActivityView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
}

@MainActor final class LockScreenActivityController {
    static let unlockDuration: TimeInterval = 0.12
    static let unlockScale: CGFloat = 0.96
    private static let exitAnimationKey = "ordinary.lock-activity.exit"
    private(set) var panel: LockScreenActivityPanel?
    private var host: NSHostingView<LockScreenActivityView>?
    private var placement: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private var space: (any LockScreenSpaceDelegating)?
    private var generation = UUID()
    private var requested = false
    private var delegated = false
    private var nextPlacementAttempt: TimeInterval = 0
    private var snapshot = LockScreenActivitySnapshot()
    private var layout: LockScreenActivityLayout?
    private var pendingAction: String?
    private var unlockTimer: Timer?
    private var reduceMotion = false
    private var dismissedForUnlock = false
    private var unlockAttemptID: UUID?
    private var unlockAttemptTask: Task<Void, Never>?
    private var loginAreaVisible = true
    private var presentationScreen: CGRect?
    private var loginVisibilityObservers: [NSObjectProtocol] = []
    private var loginHideTask: Task<Void, Never>?
    var pollsForUnlock: Bool { unlockTimer != nil }
    var awaitingUnlock: Bool { unlockAttemptID != nil }
    var onAction: (LockScreenActivityAction) -> String? = { _ in nil }
    var availableOutputs: () -> [AudioOutput.Device] = { AudioOutput.devices() }
    var onSelectOutput: (AudioOutput.Device, MusicContentIdentity) -> Bool = { _, _ in false }
    var onUnlock: () -> Void = {}
    var onRestoreAfterUnlockAttempt: () -> Void = {}
    private let readLock: @MainActor () -> SessionLockSnapshot
    private let getSpace: @MainActor () -> (any LockScreenSpaceDelegating)?
    private let displayAwake: @MainActor (NSScreen?) -> Bool

    init(readLock: @escaping @MainActor () -> SessionLockSnapshot = SessionLockSnapshot.read,
         getSpace: @escaping @MainActor () -> (any LockScreenSpaceDelegating)? = { LockScreenSpace.shared },
         displayAwake: @escaping @MainActor (NSScreen?) -> Bool = DisplayPowerService.isAwake) {
        self.readLock = readLock; self.getSpace = getSpace; self.displayAwake = displayAwake
        // loginwindow publishes these when its account/password UI appears and
        // disappears. Keep the login space reserved until macOS confirms hidden.
        for (name, visible) in [("com.apple.screenLockUIIsShown", true), ("com.apple.screenLockUIIsHidden", false)] {
            loginVisibilityObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.loginAreaChanged(visible: visible) }
                })
        }
    }
    deinit {
        unlockTimer?.invalidate(); unlockAttemptTask?.cancel(); loginHideTask?.cancel()
        loginVisibilityObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
    func beginLockedSession() {
        loginHideTask?.cancel(); loginHideTask = nil
        loginAreaVisible = true
        cancelUnlockAttempt()
        guard dismissedForUnlock else { return }
        finishHiding()
        dismissedForUnlock = false
    }
    func update(visible: Bool, snapshot: LockScreenActivitySnapshot, screen: CGRect?,
                animateExit: Bool = false, reduceMotion: Bool = false, pendingAction: String? = nil) {
        self.reduceMotion = reduceMotion
        guard visible else { hide(animated: animateExit, reduceMotion: reduceMotion); return }
        // Cached hover/context events can still describe the preceding lock.
        // Only the next lock notification may present this panel again.
        guard !dismissedForUnlock else { return }
        let lock = readLock()
        if !lock.locked, lock.currentConsoleUser {
            dismissForUnlock(reduceMotion: reduceMotion)
            onUnlock()
            return
        }
        guard lock.locked, lock.currentConsoleUser, let screen,
              let layout = LockScreenActivityLayout.make(screen: screen, snapshot: snapshot, loginAreaVisible: loginAreaVisible) else {
            hide(animated: animateExit && lock.locked && lock.currentConsoleUser, reduceMotion: reduceMotion); return
        }
        if exitTask != nil { finishHiding() }
        presentationScreen = screen
        requested = true
        if panel == nil {
            let panel = LockScreenActivityPanel(contentRect: layout.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Ordinary Notch"
            panel.isReleasedWhenClosed = false; panel.isOpaque = false
            panel.backgroundColor = .clear; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
            panel.sharingType = .none; panel.animationBehavior = .none
            panel.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenAuxiliary]
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            panel.appearance = NSAppearance(named: .darkAqua)
            let host = LockScreenActivityHostingView(rootView: LockScreenActivityView(snapshot: snapshot, lockScreenAppearance: true))
            host.sizingOptions = []; host.safeAreaRegions = []
            // Each activity supplies its own surface; the gaps stay transparent.
            panel.contentView = host
            panel.contentView?.wantsLayer = true
            self.panel = panel; self.host = host
        }
        guard let panel else { return }
        let layoutChanged = self.layout != layout
        if self.snapshot != snapshot || self.layout != layout || self.pendingAction != pendingAction {
            self.snapshot = snapshot; self.layout = layout; self.pendingAction = pendingAction
            refreshContent()
            if layoutChanged {
                if delegated && panel.isVisible && !reduceMotion {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.2
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        panel.animator().setFrame(layout.frame, display: false)
                    }
                } else { panel.setFrame(layout.frame, display: false) }
            }
        }
        guard displayAwake(panel.screen) else { hide(); return }
        guard !delegated, placement == nil, ProcessInfo.processInfo.systemUptime >= nextPlacementAttempt else { return }
        nextPlacementAttempt = ProcessInfo.processInfo.systemUptime + 30
        guard let space = getSpace() else { return }
        self.space = space
        let token = UUID(); generation = token
        placement = Task { [weak self] in
            let moved = await space.delegate(panel)
            guard let self, self.generation == token else { return }
            placement = nil
            let lock = readLock()
            guard !Task.isCancelled, requested, lock.locked, lock.currentConsoleUser, displayAwake(panel.screen),
                  let layout = self.layout else { hide(); return }
            guard moved else {
                panel.orderOut(nil); space.undelegate(panel); self.space = nil
                return
            }
            delegated = true
            panel.ignoresMouseEvents = false
            panel.alphaValue = 0
            panel.setFrame(reduceMotion ? layout.frame : layout.frame.offsetBy(dx: 0, dy: -10), display: false)
            panel.orderFrontRegardless()
            startUnlockObservation()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotion ? 0.12 : 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(layout.frame, display: false)
            }, completionHandler: nil)
        }
    }
    func loginAreaChanged(visible: Bool) {
        loginHideTask?.cancel(); loginHideTask = nil
        let lock = readLock()
        guard lock.locked, lock.currentConsoleUser, !dismissedForUnlock else { return }
        if visible {
            applyLoginAreaVisibility(true)
        } else {
            // The same hidden signal also arrives during unlock. Let the fast
            // exit win rather than dropping the cards as authentication ends.
            loginHideTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                let lock = readLock()
                guard lock.locked, lock.currentConsoleUser, !dismissedForUnlock else { return }
                applyLoginAreaVisibility(false)
                loginHideTask = nil
            }
        }
    }
    private func applyLoginAreaVisibility(_ visible: Bool) {
        guard loginAreaVisible != visible else { return }
        loginAreaVisible = visible
        guard requested, let screen = presentationScreen else { return }
        update(visible: true, snapshot: snapshot, screen: screen, reduceMotion: reduceMotion, pendingAction: pendingAction)
    }
    private func startUnlockObservation() {
        guard unlockTimer == nil else { return }
        // Only the visible lock-screen panel uses this lightweight session read.
        // Never wait for the one-second foreground/Accessibility refresh to exit.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLockState() }
        }
        timer.tolerance = 0.005
        unlockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func checkLockState() {
        guard requested, delegated, panel?.isVisible == true else { return }
        let lock = readLock()
        guard lock.currentConsoleUser else { hide(); return }
        if !lock.locked {
            dismissForUnlock(reduceMotion: reduceMotion)
            onUnlock()
        }
    }
    func dismissForUnlock(reduceMotion: Bool) {
        cancelUnlockAttempt()
        guard !dismissedForUnlock else { return }
        dismissedForUnlock = true
        hide(animated: true, reduceMotion: reduceMotion, unlocking: true)
    }
    /// Start the visual exit before loginwindow finishes authenticating. This
    /// never grants access or resumes app actions; those still require unlock.
    func beginUnlockAttempt(id: UUID = UUID(), reduceMotion: Bool, recoveryTimeout: TimeInterval = 2) {
        guard !dismissedForUnlock else { return }
        let lock = readLock()
        guard lock.currentConsoleUser, displayAwake(panel?.screen) else { return }
        guard lock.locked else {
            dismissForUnlock(reduceMotion: reduceMotion); onUnlock(); return
        }
        dismissForUnlock(reduceMotion: reduceMotion)
        unlockAttemptID = id
        let deadline = ContinuousClock.now + .seconds(recoveryTimeout)
        unlockAttemptTask = Task { [weak self] in
            repeat {
                do { try await Task.sleep(for: .milliseconds(50)) }
                catch { return }
                guard let self, self.unlockAttemptID == id else { return }
                let lock = self.readLock()
                guard lock.currentConsoleUser, self.displayAwake(self.panel?.screen) else {
                    self.hide(); return
                }
                if !lock.locked {
                    self.dismissForUnlock(reduceMotion: reduceMotion)
                    self.onUnlock()
                    return
                }
            } while ContinuousClock.now < deadline
            self?.finishUnlockAttempt(id: id)
        }
    }
    func finishUnlockAttempt(id: UUID) {
        guard unlockAttemptID == id else { return }
        let lock = readLock()
        guard lock.currentConsoleUser, displayAwake(panel?.screen) else { hide(); return }
        if !lock.locked {
            dismissForUnlock(reduceMotion: reduceMotion); onUnlock()
        } else {
            // Failed/cancelled password entry or an early/stale system signal.
            beginLockedSession()
            onRestoreAfterUnlockAttempt()
        }
    }
    private func cancelUnlockAttempt() {
        unlockAttemptTask?.cancel(); unlockAttemptTask = nil
        unlockAttemptID = nil
    }
    func hide(animated: Bool = false, reduceMotion: Bool = false) {
        if unlockAttemptID != nil {
            cancelUnlockAttempt()
            dismissedForUnlock = false
        }
        if animated, !dismissedForUnlock, panel?.isVisible == true {
            let lock = readLock()
            if !lock.locked && lock.currentConsoleUser {
                dismissForUnlock(reduceMotion: reduceMotion)
                return
            }
        }
        hide(animated: animated, reduceMotion: reduceMotion, unlocking: false)
    }
    private func hide(animated: Bool, reduceMotion: Bool, unlocking: Bool) {
        loginHideTask?.cancel(); loginHideTask = nil
        cancelMenus(in: panel?.contentView)
        panel?.ignoresMouseEvents = true
        unlockTimer?.invalidate(); unlockTimer = nil
        if exitTask != nil {
            if !animated { finishHiding() }
            return
        }
        guard requested || delegated || placement != nil || panel?.isVisible == true else { return }
        requested = false; generation = UUID()
        placement?.cancel(); placement = nil
        let lock = readLock()
        guard animated, (lock.locked || unlocking), lock.currentConsoleUser, let panel, panel.isVisible,
              displayAwake(panel.screen) else { finishHiding(); return }
        let token = generation
        let duration = reduceMotion ? 0.08 : Self.unlockDuration
        if !reduceMotion, let layer = panel.contentView?.layer {
            // Scale the actual glass surface about its center without resizing
            // the window or reflowing the text during dismissal.
            let x = layer.bounds.width * (0.5 - layer.anchorPoint.x)
            let y = layer.bounds.height * (0.5 - layer.anchorPoint.y)
            var transform = CATransform3DMakeTranslation(x, y, 0)
            transform = CATransform3DScale(transform, Self.unlockScale, Self.unlockScale, 1)
            transform = CATransform3DTranslate(transform, -x, -y, 0)
            let scale = CABasicAnimation(keyPath: "transform")
            scale.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            scale.toValue = NSValue(caTransform3D: transform)
            scale.duration = duration
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.transform = transform
            layer.add(scale, forKey: Self.exitAnimationKey)
            CATransaction.commit()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        }, completionHandler: nil)
        CATransaction.flush()
        exitTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) }
            catch { return }
            guard let self, self.generation == token, !self.requested else { return }
            finishHiding()
        }
    }
    private func finishHiding() {
        exitTask?.cancel(); exitTask = nil
        unlockTimer?.invalidate(); unlockTimer = nil
        requested = false; generation = UUID()
        placement?.cancel(); placement = nil
        if let panel {
            panel.orderOut(nil)
            // Keep the outgoing surface in its original space until invisible.
            space?.undelegate(panel)
            if let layer = panel.contentView?.layer {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                layer.removeAnimation(forKey: Self.exitAnimationKey)
                layer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
            panel.alphaValue = 1
        }
        space = nil; delegated = false
        nextPlacementAttempt = 0
        snapshot = .init(); pendingAction = nil
        host?.rootView = LockScreenActivityView(snapshot: .init())
        layout = nil
    }
    private func refreshContent() {
        host?.rootView = LockScreenActivityView(snapshot: snapshot, lockScreenAppearance: true,
            pendingAction: pendingAction, action: { [weak self] in self?.perform($0) },
            availableOutputs: { [weak self] in
                guard let self, allowsActions else { return [] }
                return availableOutputs()
            }, selectOutput: { [weak self] in self?.selectOutput($0, for: $1) ?? false })
    }
    private func cancelMenus(in view: NSView?) {
        (view as? NotchPressAndHoldControl)?.cancelMenu()
        view?.subviews.forEach { cancelMenus(in: $0) }
    }
    private var allowsActions: Bool {
        let lock = readLock()
        return requested && delegated && panel?.isVisible == true && lock.locked && lock.currentConsoleUser
            && displayAwake(panel?.screen)
    }
    func selectOutput(_ device: AudioOutput.Device, for identity: MusicContentIdentity) -> Bool {
        guard allowsActions else { return false }
        return onSelectOutput(device, identity)
    }
    func perform(_ action: LockScreenActivityAction) {
        guard allowsActions else { return }
        pendingAction = onAction(action)
        refreshContent()
    }
}
