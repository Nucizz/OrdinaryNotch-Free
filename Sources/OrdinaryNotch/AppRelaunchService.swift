import Foundation

enum AppRelaunchService {
    // Wait for the old process to release its single-instance lock before opening.
    // Paths are positional arguments, never interpolated into shell source.
    static let waitScript = """
    attempts=0
    while /bin/kill -0 "$1" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 100 ] || exit 1
        /bin/sleep 0.1
    done
    exec "$3" -n "$2"
    """

    static func schedule() throws {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", waitScript, "ordinary-notch-reopen",
                            String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path, "/usr/bin/open"]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
    }
}
