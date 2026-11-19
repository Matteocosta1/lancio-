import SwiftUI
import UIKit

// MARK: - Cosa si lancia

enum Contenuto {
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
}

/// Dove arriva: sul Mac con lo stesso Apple ID (zero tocchi) o sul Mac di un'altra persona (AirDrop, un tocco).
enum Destinazione: String, CaseIterable, Identifiable {
    case mio = "Mio"
    case altri = "Altri"
    var id: String { rawValue }
}

// MARK: - La consegna
// Niente da installare sul Mac: si usano solo i servizi di Apple.
//   Mio   → Appunti Universali (testo, link e foto pronti con ⌘V sul Mac), Handoff per il link (icona nel Dock),
//           e la foto anche in iCloud Drive › Lancio, così resta salvata.
//   Altri → il foglio di condivisione con AirDrop in cima: si tocca il Mac. Apple non permette di sceglierlo da soli.

enum Consegna {
    /// L'attività Handoff del link: deve restare viva finché il Mac la mostra nel Dock.
    private static var handoff: NSUserActivity?

    /// Consegna al Mac con lo stesso Apple ID. Torna la frase che dice dove trovarlo.
    static func mio(_ contenuto: Contenuto) async -> String {
        switch contenuto {
        case .testo(let testo):
            UIPasteboard.general.string = testo
            return "Sul Mac premi ⌘V dove vuoi."

        case .link(let url):
            UIPasteboard.general.url = url
            handoff?.invalidate()
            let attivita = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            attivita.webpageURL = url
            attivita.isEligibleForHandoff = true
            attivita.becomeCurrent()
            handoff = attivita
            return "Sul Mac: icona col badge iPhone nel Dock, oppure ⌘V."

        case .foto(let immagine, let dati):
            UIPasteboard.general.image = immagine
            let salvata = await salvaInICloud(dati, nome: nomeFile())
            return salvata
                ? "Sul Mac: ⌘V, e anche in iCloud Drive › Lancio."
                : "Sul Mac: ⌘V. iCloud Drive non è attivo su questo iPhone."
        }
    }

    /// Apre AirDrop per il Mac di un'altra persona. `fine(true)` se è stato inviato.
    static func altri(_ contenuto: Contenuto, fine: @escaping @MainActor (Bool) -> Void) {
        let oggetto: Any
        switch contenuto {
        case .foto(let immagine, _): oggetto = immagine
        case .link(let url): oggetto = url
        case .testo(let testo): oggetto = testo
        }
        let foglio = UIActivityViewController(activityItems: [oggetto], applicationActivities: nil)
        // via le voci di Apple che non c'entrano: resta AirDrop in cima (le app di altri non si possono togliere)
        foglio.excludedActivityTypes = [
            .addToReadingList, .assignToContact, .copyToPasteboard, .mail, .markupAsPDF,
            .message, .openInIBooks, .print, .saveToCameraRoll
        ]
        foglio.completionWithItemsHandler = { tipo, completato, _, _ in
            let inviato = completato && tipo == .airDrop
            Task { @MainActor in fine(inviato) }
        }
        guard let sopra = controllerInCima() else { fine(false); return }
        foglio.popoverPresentationController?.sourceView = sopra.view
        sopra.present(foglio, animated: true)
    }

    // MARK: Dettagli

    private static func nomeFile() -> String {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "it_IT")
        formato.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        return "Lancio \(formato.string(from: Date())).jpg"
    }

    /// Scrive la foto nella cartella «Lancio» di iCloud Drive (si vede nel Finder del Mac).
    /// Fuori dal thread principale: Apple chiede di non cercare iCloud da lì.
    @concurrent
    private nonisolated static func salvaInICloud(_ dati: Data, nome: String) async -> Bool {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return false }
        let cartella = base.appending(path: "Documents", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
            try dati.write(to: cartella.appending(path: nome), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func controllerInCima() -> UIViewController? {
        let finestre = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var cima = finestre.first(where: \.isKeyWindow)?.rootViewController
        while let sopra = cima?.presentedViewController { cima = sopra }
        return cima
    }
}
