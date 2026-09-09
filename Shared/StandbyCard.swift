import SwiftUI
import Tub3Core

/// The box answered, and it is not finished being set up.
///
/// Distinct from the fault slate on purpose. "No signal" tells someone to go and look at
/// their network; the actual answer is a form on the box's own web page, so the address goes
/// on screen in gold and is the largest thing after the headline. This is the state a brand
/// new box is in for as long as it takes to point it at a Plex server — which is to say, the
/// most likely thing anyone ever sees the very first time they turn this on.
struct StandbyCard: View {
    let headline: String
    let detail: String
    /// The box's own address, as typed into a browser.
    let address: String

    var body: some View {
        VStack(spacing: 18) {
            Text(headline)
                .font(Theme.furniture(72, .bold))
                .foregroundStyle(Theme.phosphor)
            Text(detail)
                .font(Theme.furniture(32))
                .foregroundStyle(Theme.dim)
            Text(BoxAddress.forDisplay(address))
                .font(Theme.furniture(44, .semibold))
                .foregroundStyle(Theme.gold)
                .padding(.top, 20)
                .accessibilityIdentifier("tub3.standby.address")
            Text("Open that on a computer or a phone to finish setting it up.")
                .font(Theme.furniture(26))
                .foregroundStyle(Theme.dim)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ink)
        .accessibilityIdentifier("tub3.standby")
    }

}
