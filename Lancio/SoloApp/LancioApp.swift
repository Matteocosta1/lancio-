import SwiftUI
import UIKit

@main
struct LancioApp: App {
    @UIApplicationDelegateAdaptor(DelegatoLancio.self) private var delegato

    var body: some Scene {
        WindowGroup {
            VistaLancio()
        }
    }
}

/// Serve solo per lo schermo esterno (AirPlay sul Mac): quando si collega, Lancio ci disegna la sua schermata.
/// In JARVIS lo stesso metodo va nel delegato che c'è già (vedi PER-JARVIS.md).
final class DelegatoLancio: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        SchermoLancio.configurazione(per: connectingSceneSession) ?? connectingSceneSession.configuration
    }
}
