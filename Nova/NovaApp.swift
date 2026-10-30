import SwiftUI
import AVFoundation

@main
struct NovaApp: App {
    init() {
        // Permite que el audio de las apps siga sonando al cambiar de pestaña o salir de Nova.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
