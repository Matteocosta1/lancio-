import AVFoundation
import UIKit

// MARK: - I suoni di JARVIS (solo per l'app Lancio da sola)
// Stessi nomi e stessi file di JARVIS: il codice del Modulo chiama `Suoni.tocco()`, `Suoni.fatto()`… e in JARVIS
// trova gli originali. Qui ci sono solo le funzioni che usa Lancio. In JARVIS questo file NON si copia.

enum Suoni {
    private static var lettori: [AVAudioPlayer] = []
    private static var lettoreScheda: AVAudioPlayer?
    private static var audioPronto = false

    /// Tocco su un tasto: il «tick» di JARVIS e il clic del Taptic Engine.
    static func tocco() { ApticaLancio.click(); suona("tick") }
    /// Una sezione si apre (il caricamento HUD).
    static func schedaApre() {
        prepara()
        guard let url = file("scheda"), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 1.0
        lettoreScheda?.stop()
        lettoreScheda = p
        p.play()
    }
    /// La sezione è pronta: il suono d'apertura sfuma e parte «schedapronta».
    static func schedaPronta() {
        if let p = lettoreScheda, p.isPlaying { p.setVolume(0, fadeDuration: 0.18) }
        suona("schedapronta")
    }
    /// In JARVIS è il suono della chat che si svuota: in Lancio è il suono del lancio.
    static func chatSvuota() { suona("chatsvuota") }
    /// Fatto: la vibrazione di successo e il suono «pronto».
    static func fatto() { ApticaLancio.fatto(); suona("pronto") }
    /// Qualcosa non va (in JARVIS c'è anche un segnale sonoro).
    static func errore() { ApticaLancio.errore() }

    // MARK: Dettagli

    /// Come in JARVIS: suona anche col silenzioso; la musica di altre app continua.
    private static func prepara() {
        guard !audioPronto else { return }
        audioPronto = true
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    private static func file(_ nome: String) -> URL? {
        Bundle.main.url(forResource: nome, withExtension: "m4a")
    }

    private static func suona(_ nome: String) {
        prepara()
        guard let url = file(nome), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 1.0
        lettori.removeAll { !$0.isPlaying }
        lettori.append(p)
        p.play()
    }
}
