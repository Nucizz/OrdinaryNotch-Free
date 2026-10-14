// Adapted from jonnyoo/glance NotchSkyLight.swift and Lakr233/SkyLightWindow (MIT).
// Copyright notices and licenses: Resources/LockScreen-LICENSES.txt.
// Private macOS API. Lock-screen placement must fail closed when delegation is unavailable.
import AppKit
import OSLog

/// What Notification Center itself renders at while the screen is locked — higher
/// than the plain `screenLock` level, which is why that one is used here.
private enum ActivitySpaceLevel: Int32 {
    case notificationCenterAtScreenLock = 400
}

@MainActor
final class LockScreenSpace {
    /// `nil` if the private framework or any symbol couldn't be loaded —
    /// callers must treat that as "lock-screen visibility unavailable,"
    /// not a crash.
    static let shared: LockScreenSpace? = LockScreenSpace()

    private let log = Logger(subsystem: "dev.ordinary.notch", category: "LockScreen")
    private var moves: [Int: UUID] = [:]
    private let connection: Int32
    private let space: UInt64

    private typealias F_SLSMainConnectionID = @convention(c) () -> Int32
    private typealias F_SLSSpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias F_SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias F_SLSSpaceGetAbsoluteLevel = @convention(c) (Int32, UInt64) -> Int32
    private typealias F_SLSShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias F_SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void
    private typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias F_SLSCopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private let copySpacesForWindows: F_SLSCopySpacesForWindows
    private let addWindowsAndRemoveFromSpaces: F_SLSSpaceAddWindowsAndRemoveFromSpaces
    private let removeWindowsFromSpaces: F_SLSRemoveWindowsFromSpaces

    private init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else { return nil }

        guard
            let mainConnectionSym = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreateSym = dlsym(handle, "SLSSpaceCreate"),
            let getLevelSym = dlsym(handle, "SLSSpaceGetAbsoluteLevel"),
            let copySpacesSym = dlsym(handle, "SLSCopySpacesForWindows"),
            let setLevelSym = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpacesSym = dlsym(handle, "SLSShowSpaces"),
            let addRemoveSym = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
            let removeSym = dlsym(handle, "SLSRemoveWindowsFromSpaces")
        else { dlclose(handle); return nil }

        let mainConnectionID = unsafeBitCast(mainConnectionSym, to: F_SLSMainConnectionID.self)
        let spaceCreate = unsafeBitCast(spaceCreateSym, to: F_SLSSpaceCreate.self)
        let getAbsoluteLevel = unsafeBitCast(getLevelSym, to: F_SLSSpaceGetAbsoluteLevel.self)
        copySpacesForWindows = unsafeBitCast(copySpacesSym, to: F_SLSCopySpacesForWindows.self)
        let setAbsoluteLevel = unsafeBitCast(setLevelSym, to: F_SLSSpaceSetAbsoluteLevel.self)
        let showSpaces = unsafeBitCast(showSpacesSym, to: F_SLSShowSpaces.self)
        addWindowsAndRemoveFromSpaces = unsafeBitCast(addRemoveSym, to: F_SLSSpaceAddWindowsAndRemoveFromSpaces.self)
        removeWindowsFromSpaces = unsafeBitCast(removeSym, to: F_SLSRemoveWindowsFromSpaces.self)

        connection = mainConnectionID()
        // The `1` flag is load-bearing: any other value causes Finder to draw desktop icons into this space.
        space = spaceCreate(connection, 1, nil)
        guard space > 0 else { return nil }
        let level = ActivitySpaceLevel.notificationCenterAtScreenLock.rawValue
        // These setters return void. Validate the resulting state, not an
        // undefined register value. Space IDs are 64-bit on supported Macs.
        setAbsoluteLevel(connection, space, level)
        guard getAbsoluteLevel(connection, space) == level else { return nil }
        showSpaces(connection, [space] as CFArray)
    }

    /// Adds `window` to the elevated-level space, making it visible on the
    /// lock screen. Call only while actually locked.
    func delegate(_ window: NSWindow) async -> Bool {
        guard SessionLockSnapshot.read().locked else { return false }
        let windowID = window.windowNumber
        let token = UUID(); moves[windowID] = token
        let windows = [windowID] as CFArray
        addWindowsAndRemoveFromSpaces(connection, space, windows, 7)
        // 7 queries user spaces only; this lock-screen space is OS-owned.
        // Include both classes (1 | 2 | 4 | 8) and allow WindowServer to apply
        // the move before validating membership. A synchronous read can lag.
        for _ in 0..<12 {
            let lock = SessionLockSnapshot.read()
            guard moves[windowID] == token, !Task.isCancelled, lock.locked, lock.currentConsoleUser else { break }
            if let spaces = copySpacesForWindows(connection, 15, windows)?.takeRetainedValue() as? [NSNumber],
               spaces.contains(where: { $0.uint64Value == space }) {
                log.notice("Lock-screen notch placement confirmed")
                return true
            }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
        }
        if moves[windowID] == token {
            if !Task.isCancelled { log.error("Lock-screen notch placement could not be confirmed") }
            undelegate(window)
        }
        return false
    }

    /// Removes `window` from the elevated-level space, returning it to
    /// normal window-server behavior. Call as soon as the screen unlocks.
    func undelegate(_ window: NSWindow) {
        moves.removeValue(forKey: window.windowNumber)
        removeWindowsFromSpaces(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
