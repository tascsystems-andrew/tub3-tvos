import SwiftUI
import Tub3Core

@main
struct TVApp: App {
    @State private var tuner: Tuner = {
        let box = BoxClient(base: AppConfig.boxURL)
        return Tuner(box: box, engine: PlayerEngine(), clientID: AppConfig.clientID)
    }()

    var body: some Scene {
        WindowGroup {
            TunerScreen(tuner: tuner)
        }
    }
}
