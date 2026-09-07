import SwiftUI

/// The corner ident. Number in gold, station in purple, exactly as the box draws it.
public struct ChannelBugView: View {
    let channel: Int
    let station: String

    public init(channel: Int, station: String) {
        self.channel = channel
        self.station = station
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(channel)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
                .accessibilityIdentifier("tub3.channel.number")
            Text(station)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.purple)
                .accessibilityIdentifier("tub3.channel.station")
        }
        .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
    }
}
