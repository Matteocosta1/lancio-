import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - L'estensione «Lancia» del tasto Condividi
// iOS la apre quando, in Foto, Safari o un'altra app, tocchi Condividi › Lancia. Legge quello che le passano
// (una foto, un link o un testo) e mostra la scheda di lancio (VistaCondividiLancio).

final class ControllerCondividi: UIViewController {
    private let stato = StatoCondividiLancio()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)
        let vista = VistaCondividiLancio(stato: stato, fine: { [weak self] in self?.chiudi() },
                                         annulla: { [weak self] in self?.annulla() })
        let ospite = UIHostingController(rootView: vista)
        addChild(ospite)
        ospite.view.frame = view.bounds
        ospite.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(ospite.view)
        ospite.didMove(toParent: self)
        leggi()
    }

    /// Prende il primo allegato utile, in quest'ordine: foto, link, testo.
    private func leggi() {
        let elementi = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let allegati = elementi.flatMap { $0.attachments ?? [] }
        let stato = self.stato

        if let foto = allegati.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            _ = foto.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { dati, _ in
                let jpeg = dati.flatMap { ImmagineLancio.jpegRidotto($0) }
                Task { @MainActor in stato.arrivaFoto(jpeg) }
            }
        } else if let link = allegati.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            _ = link.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in stato.arrivaLink(url) }
            }
        } else if let testo = allegati.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            _ = testo.loadObject(ofClass: String.self) { stringa, _ in
                Task { @MainActor in stato.arrivaTesto(stringa) }
            }
        } else {
            stato.niente()
        }
    }

    private func chiudi() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func annulla() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
