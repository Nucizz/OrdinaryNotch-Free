import Carbon

/// Ordinary Dock/menu quits close Settings; explicit quit and system shutdown still stop us.
enum NotchTerminationPolicy {
    static func shouldTerminate(explicitQuit: Bool, reason: OSType?) -> Bool {
        explicitQuit || reason.map { [OSType(kAEQuitAll), OSType(kAEShutDown), OSType(kAERestart), OSType(kAEReallyLogOut), OSType(kAELogOut)].contains($0) } == true
    }
}
