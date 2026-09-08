import SwiftUI

/// What a channel shows when there is no picture: honest, and never a spinner forever.
public struct SlateView: View {
    let channel: Int
    let station: String
    let message: String

    public init(channel: Int, station: String, message: String) {
        self.channel = channel
        self.station = station
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("\(channel)")
                .font(.system(size: 120, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.gold)
            Text(station)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.purple)
            Text(message)
                .font(.system(size: 24, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
    }
}
