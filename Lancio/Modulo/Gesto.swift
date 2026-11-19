#if os(iOS)
import SwiftUI
import UIKit
import Combine
import CoreMotion

// MARK: - Il gesto del lancio
// Il giroscopio dice quanto in fretta il telefono ruota, l'accelerometro quanto forte è lo scatto. Letti 100 volte
// al secondo: quando la rotazione in avanti è molto veloce e insieme c'è una spinta, è un lancio.
// Il gesto conta solo se l'app è aperta e c'è qualcosa «in mano» (`armato`): niente lanci per sbaglio in tasca.
// Su iPhone non serve nessun permesso per questi sensori.

final class Lanciatore: ObservableObject {
    /// Quanto è forte il movimento adesso, da 0 a 1 (la barra «Forza»). Scende piano dopo un picco.
    @Published private(set) var forza: Double = 0
    /// Il telefono ha i sensori di movimento (sul simulatore no).
    let disponibile: Bool

    /// Si lancia solo con qualcosa in mano.
    var armato = false
    /// Cosa fare quando il lancio è riconosciuto.
    var alLancio: (() -> Void)?

    private let sensori = CMMotionManager()
    private var picco: Double = 0
    private var ultimoLancio = Date.distantPast

    // Soglie: rotazione in rad/s, spinta in g (1 g = il peso del telefono). Si regolano provando sul telefono.
    private let rotazioneLancio = 5.5
    private let spintaConRotazione = 1.1
    private let spintaDaSola = 2.6

    init() {
        disponibile = sensori.isDeviceMotionAvailable
    }

    func accendi() {
        guard disponibile, !sensori.isDeviceMotionActive else { return }
        sensori.deviceMotionUpdateInterval = 1.0 / 100.0
        sensori.startDeviceMotionUpdates(to: .main) { [weak self] dati, _ in
            guard let dati else { return }
            let rotazione = dati.rotationRate
            let spinta = dati.userAcceleration
            MainActor.assumeIsolated {
                self?.leggi(rotazione: rotazione, spinta: spinta)
            }
        }
    }

    func spegni() {
        sensori.stopDeviceMotionUpdates()
        picco = 0
        forza = 0
    }

    private func leggi(rotazione: CMRotationRate, spinta: CMAcceleration) {
        // la rotazione in avanti è attorno all'asse orizzontale del telefono (x); il verso non conta
        let giro = abs(rotazione.x)
        let colpo = (spinta.x * spinta.x + spinta.y * spinta.y + spinta.z * spinta.z).squareRoot()

        let adesso = min(1, max(giro / 7, colpo / spintaDaSola))
        picco = max(adesso, picco * 0.9)
        if abs(picco - forza) > 0.02 { forza = picco }

        let lancio = (giro > rotazioneLancio && colpo > spintaConRotazione) || colpo > spintaDaSola
        guard lancio, armato, Date().timeIntervalSince(ultimoLancio) > 1.2 else { return }
        ultimoLancio = Date()
        alLancio?()
    }
}

// MARK: - La vibrazione del lancio
// Stesse regole di JARVIS: una vibrazione conferma un evento, mai decorazione.
enum ApticaLancio {
    private static let selezione = UISelectionFeedbackGenerator()
    private static let colpo = UIImpactFeedbackGenerator(style: .heavy)
    private static let notifica = UINotificationFeedbackGenerator()

    /// Il tocco su un tasto.
    static func click() { selezione.selectionChanged() }
    /// Il contenuto parte: un colpo secco.
    static func lancio() { colpo.impactOccurred(intensity: 1) }
    /// Arrivato.
    static func fatto() { notifica.notificationOccurred(.success) }
    /// Manca qualcosa.
    static func errore() { notifica.notificationOccurred(.warning) }
}
#endif
