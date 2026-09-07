import Foundation

/// A trace you can read off a television.
///
/// The app runs on an appliance with no debugger attached and no console of its own, so when
/// a channel misbehaves in the living room there is otherwise nothing to go on but a photo of
/// the screen. Enabled with `-tub3Trace`, which `devicectl ... --console` can pass at launch.
public enum Diag {
    public static let on = ProcessInfo.processInfo.arguments.contains("-tub3Trace")

    public static func log(_ message: @autoclosure () -> String) {
        guard on else { return }
        print("TUB3 \(String(format: "%.3f", Date().timeIntervalSince1970)) \(message())")
        fflush(stdout)
    }
}
