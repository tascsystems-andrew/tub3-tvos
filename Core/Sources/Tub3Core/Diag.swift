import Foundation
import os

/// A trace you can read off a television.
///
/// The app runs on an appliance with no debugger attached and no console of its own, so when
/// a channel misbehaves in the living room there is otherwise nothing to go on but a photo of
/// the screen. Enabled with `-tub3Trace`, which `devicectl ... --console` can pass at launch.
public enum Diag {
    public static let on = ProcessInfo.processInfo.arguments.contains("-tub3Trace")

    /// Where the trace goes, and it goes to two places on purpose.
    ///
    /// `print` is what `devicectl ... --console` picks up, which is how this is read off a
    /// television. The unified log is what `simctl spawn <sim> log stream` picks up, which is
    /// how it is read out of a simulator under `xcodebuild test` — a test runner does not
    /// capture the app's stdout, so a trace that only printed was invisible exactly where a
    /// test could have asserted on it.
    private static let unified = Logger(subsystem: "com.tascsystems.tub3", category: "trace")

    public static func log(_ message: @autoclosure () -> String) {
        guard on else { return }
        let line = message()
        print("TUB3 \(String(format: "%.3f", Date().timeIntervalSince1970)) \(line)")
        fflush(stdout)
        unified.notice("TUB3 \(line, privacy: .public)")
    }

    /// Ask the network layer what it thinks of a URL that AVFoundation refused.
    ///
    /// AVFoundation reports a stream failure as one flat sentence. When the same URL plays
    /// from a Mac and not from the television, that sentence is the whole of the evidence,
    /// and it is not enough to tell a refusal by the server from a refusal by the client.
    public static func probe(_ url: URL) async {
        guard on else { return }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            log("probe HTTP \(http?.statusCode ?? -1) bytes=\(data.count) type=\(http?.value(forHTTPHeaderField: "Content-Type") ?? "-")")
        } catch {
            let e = error as NSError
            log("probe FAILED domain=\(e.domain) code=\(e.code) \(e.localizedDescription)")
            if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError {
                log("   underlying domain=\(u.domain) code=\(u.code) \(u.localizedDescription)")
            }
        }
    }
}
