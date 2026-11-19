#if os(iOS)
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - La foto pronta per il lancio
// Le foto dell'iPhone possono essere enormi (48 MP): aperte intere riempirebbero la memoria, e dal tasto Condividi
// la memoria è poca. Qui si riducono a un JPEG di al massimo 3072 pixel per lato, girato nel verso giusto:
// sul Mac si vede benissimo e arriva in fretta.

enum ImmagineLancio {
    nonisolated static func jpegRidotto(_ dati: Data, lato: Int = 3072) -> Data? {
        guard let sorgente = CGImageSourceCreateWithData(dati as CFData, nil) else { return nil }
        let opzioni: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lato
        ]
        guard let immagine = CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary) else { return nil }
        let uscita = NSMutableData()
        guard let destinazione = CGImageDestinationCreateWithData(uscita, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destinazione, immagine, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destinazione) else { return nil }
        return uscita as Data
    }
}
#endif
