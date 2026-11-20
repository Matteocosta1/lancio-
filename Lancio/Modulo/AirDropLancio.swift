#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Altri: AirDrop
// Solo nell'app (dal tasto Condividi c'è già AirDrop nel foglio di iOS): qui si apre il foglio con AirDrop in cima.

extension ConsegnaLancio {
    /// Apre AirDrop per il Mac di un'altra persona. `fine(true)` se è stato inviato.
    static func altri(_ contenuto: ContenutoLancio, fine: @escaping @MainActor (Bool) -> Void) {
        let oggetto: Any
        switch contenuto {
        case .foto(let immagine, _): oggetto = immagine
        case .video(let url): oggetto = url
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

    fileprivate static func controllerInCima() -> UIViewController? {
        let finestre = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
            .flatMap(\.windows)
        var cima = finestre.first(where: \.isKeyWindow)?.rootViewController ?? finestre.first?.rootViewController
        while let sopra = cima?.presentedViewController { cima = sopra }
        return cima
    }
}
#endif
