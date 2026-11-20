#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Cosa si lancia

enum ContenutoLancio {
    case foto(UIImage, Data)
    case link(URL)
    case testo(String)

    /// Il nome breve da mostrare («una foto», «un link», «un testo»).
    var nome: String {
        switch self {
        case .foto: return "una foto"
        case .link: return "un link"
        case .testo: return "un testo"
        }
    }

    /// «foto», «link» o «testo»: viaggia nell'invito, così chi riceve sa cosa sta per arrivare.
    var tipo: String {
        switch self {
        case .foto: return "foto"
        case .link: return "link"
        case .testo: return "testo"
        }
    }

    /// Un'impronta del contenuto: cambia quando cambia la foto, la pagina o il testo «in mano».
    var chiave: String {
        switch self {
        case .foto(_, let dati): return "foto-\(dati.count)-\(dati.hashValue)"
        case .link(let url): return "link-\(url.absoluteString)"
        case .testo(let testo): return "testo-\(testo.hashValue)"
        }
    }
}

/// Dove arriva.
///   Mio     → il Mac con lo stesso Apple ID, zero tocchi.
///   Altri   → il Mac di un'altra persona: AirDrop, un tocco (Apple non permette di saltarlo).
///   Schermo → il Mac collegato in AirPlay: il contenuto atterra sul suo schermo (solo da vedere).
enum DestinazioneLancio: String, CaseIterable, Identifiable {
    case mio = "Mio"
    case altri = "Altri"
    case schermo = "Schermo"
    var id: String { rawValue }
}

// MARK: - La consegna
// Niente app sul Mac: solo servizi di Apple.
//   Mio, testo → Appunti Universali (⌘V sul Mac).
//   Mio, link  → un segnalibro in iCloud Drive › Lancio › Link: l'automazione di Comandi del Mac lo apre in Safari.
//                In più Handoff (icona nel Dock) e appunti, se l'automazione non c'è.
//   Mio, foto  → il file in iCloud Drive › Lancio › Foto: l'automazione del Mac la apre in Anteprima. In più appunti.
//   Altri      → il foglio di condivisione con AirDrop in cima: si tocca il Mac.

enum ConsegnaLancio {
    /// Il contenitore iCloud di Lancio: sul Mac compare come cartella «Lancio» in iCloud Drive.
    /// Scritto per esteso, così resta lo stesso anche dentro JARVIS.
    nonisolated static let contenitoreICloud = "iCloud.it.discosizer.lancio"

    /// L'attività Handoff del link: deve restare viva finché il Mac la mostra nel Dock.
    private static var handoff: NSUserActivity?

    /// Consegna al Mac con lo stesso Apple ID. Torna la frase che dice dove trovarlo.
    static func mio(_ contenuto: ContenutoLancio) async -> String {
        switch contenuto {
        case .testo(let testo):
            UIPasteboard.general.string = testo
            return "Negli appunti: sul Mac premi ⌘V."

        case .link(let url):
            UIPasteboard.general.url = url
            handoff?.invalidate()
            let attivita = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            attivita.webpageURL = url
            attivita.isEligibleForHandoff = true
            attivita.becomeCurrent()
            handoff = attivita
            let salvato = await salvaInICloud(segnalibro(url), cartella: "Link", nome: nomeFile(url.host() ?? "Link", estensione: "webloc"))
            return salvato
                ? "In iCloud Drive › Lancio › Link: il Mac lo apre in Safari."
                : "iCloud Drive non è attivo: sul Mac è nel Dock (Handoff) e negli appunti."

        case .foto(let immagine, let dati):
            UIPasteboard.general.image = immagine
            let salvata = await salvaInICloud(dati, cartella: "Foto", nome: nomeFile("Lancio", estensione: "jpg"))
            return salvata
                ? "In iCloud Drive › Lancio › Foto: il Mac la apre in Anteprima."
                : "iCloud Drive non è attivo: solo negli appunti (⌘V sul Mac)."
        }
    }

    // MARK: Dettagli

    private static func nomeFile(_ base: String, estensione: String) -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "it_IT")
        formato.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        let pulito = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(pulito) \(formato.string(from: Date())).\(estensione)"
    }

    /// Un segnalibro .webloc: aperto sul Mac, va dritto alla pagina.
    private static func segnalibro(_ url: URL) -> Data {
        let dizionario: [String: String] = ["URL": url.absoluteString]
        return (try? PropertyListSerialization.data(fromPropertyList: dizionario, format: .xml, options: 0)) ?? Data()
    }

    /// Scrive un file in iCloud Drive › Lancio › <cartella> (si vede nel Finder del Mac).
    /// Fuori dal thread principale: Apple chiede di non cercare iCloud da lì.
    @concurrent
    private nonisolated static func salvaInICloud(_ dati: Data, cartella: String, nome: String) async -> Bool {
        guard !dati.isEmpty,
              let base = FileManager.default.url(forUbiquityContainerIdentifier: contenitoreICloud) else { return false }
        let dove = base.appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: cartella, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: dove, withIntermediateDirectories: true)
            try dati.write(to: dove.appending(path: nome), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif
