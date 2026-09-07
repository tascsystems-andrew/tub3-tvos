import AVFoundation
import SwiftUI
import Tub3Core

/// A bare AVPlayerLayer, deliberately not AVPlayerViewController.
///
/// The system player brings transport controls, a scrubber and a title bar. This is a
/// television: you cannot scrub live broadcast, and a progress bar across the bottom of a
/// channel would give away that it is a file rather than a transmission.
#if os(tvOS) || os(iOS)
public struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    public init(player: AVPlayer) { self.player = player }

    public func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    public func updateUIView(_ view: PlayerHostView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

public final class PlayerHostView: UIView {
    public override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#endif
