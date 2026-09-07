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
