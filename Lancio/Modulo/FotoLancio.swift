#if os(iOS)
import SwiftUI
import UIKit
import Combine
import Photos

// MARK: - FOTO: le tue foto, da aprire e lanciare
// La griglia mostra le foto più recenti. Ne tocchi una: si apre a tutto schermo, scorri di lato per le altre,
// e con lo scatto del polso quella che stai guardando parte.
// In JARVIS la sezione Foto ha già il suo visore: lì basta aggiungere `.lanciabile(.foto(…))` alla foto aperta.

final class LibreriaLancio: ObservableObject {
    @Published private(set) var permesso: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var foto: [PHAsset] = []

    var consentito: Bool { permesso == .authorized || permesso == .limited }

    func prepara() async {
        if permesso == .notDetermined {
            permesso = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        if consentito { carica() }
    }

    func carica() {
        let opzioni = PHFetchOptions()
        opzioni.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opzioni.fetchLimit = 600
        let risultato = PHAsset.fetchAssets(with: .image, options: opzioni)
        foto = (0..<risultato.count).map { risultato.object(at: $0) }
    }

    /// Un'immagine della foto, grande quanto serve (miniatura o schermo intero).
    static func immagine(_ risorsa: PHAsset, lato: CGFloat) async -> UIImage? {
        await withCheckedContinuation { attesa in
            let opzioni = PHImageRequestOptions()
            opzioni.deliveryMode = .highQualityFormat       // una sola risposta: niente anteprima sfocata prima
            opzioni.resizeMode = .fast
            opzioni.isNetworkAccessAllowed = true           // anche le foto che stanno solo su iCloud
            PHImageManager.default().requestImage(for: risorsa, targetSize: CGSize(width: lato, height: lato),
                                                  contentMode: .aspectFit, options: opzioni) { immagine, _ in
                attesa.resume(returning: immagine)
            }
        }
    }

    /// La foto pronta da lanciare: JPEG ridotto a 3072 pixel, girato nel verso giusto.
    static func daLanciare(_ risorsa: PHAsset) async -> ContenutoLancio? {
        let originale: Data? = await withCheckedContinuation { attesa in
            let opzioni = PHImageRequestOptions()
            opzioni.deliveryMode = .highQualityFormat
            opzioni.isNetworkAccessAllowed = true
            opzioni.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: risorsa, options: opzioni) { dati, _, _, _ in
                attesa.resume(returning: dati)
            }
        }
        guard let originale, let jpeg = await riduci(originale), let immagine = UIImage(data: jpeg) else { return nil }
        return .foto(immagine, jpeg)
    }

    @concurrent
    private nonisolated static func riduci(_ dati: Data) async -> Data? {
        ImmagineLancio.jpegRidotto(dati)
    }
}

// MARK: - La griglia

struct VistaFotoLancio: View {
    @ObservedObject var libreria: LibreriaLancio
    let apri: (Int) -> Void

    private let tinta = Color.ciano
    private let colonne = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    var body: some View {
        Group {
            if libreria.consentito {
                if libreria.foto.isEmpty {
                    messaggio(icona: "photo", titolo: "Nessuna foto", testo: "Le foto della libreria compaiono qui.")
                } else {
                    ScrollView {
                        LazyVGrid(columns: colonne, spacing: 3) {
                            ForEach(Array(libreria.foto.enumerated()), id: \.element.localIdentifier) { indice, risorsa in
                                Button { Suoni.tocco(); apri(indice) } label: {
                                    MiniaturaLancio(risorsa: risorsa)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.bottom, 12)
                    }
                }
            } else if libreria.permesso == .notDetermined {
                ProgressView().tint(tinta)
            } else {
                messaggio(icona: "lock", titolo: "Foto chiuse",
                          testo: "Per lanciare le tue foto, Lancio deve poterle vedere: Impostazioni › Lancio › Foto.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await libreria.prepara() }
    }

    private func messaggio(icona: String, titolo: String, testo: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icona).font(.system(size: 30, weight: .light)).foregroundStyle(tinta)
            Text(titolo.uppercased())
                .font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.white)
            Text(testo)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

struct MiniaturaLancio: View {
    let risorsa: PHAsset
    @State private var immagine: UIImage?

    var body: some View {
        Color.ciano.opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let immagine {
                    Image(uiImage: immagine).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: risorsa.localIdentifier) {
                immagine = await LibreriaLancio.immagine(risorsa, lato: 320)
            }
    }
}

// MARK: - La foto aperta

struct VistaFotoApertaLancio: View {
    let foto: [PHAsset]
    @State var indice: Int
    let chiudi: () -> Void

    @State private var pronta: ContenutoLancio?
    private let tinta = Color.ciano

    var body: some View {
        TabView(selection: $indice) {
            ForEach(Array(foto.enumerated()), id: \.element.localIdentifier) { posto, risorsa in
                PaginaFotoLancio(risorsa: risorsa).tag(posto)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .lanciabile(pronta)
        .overlay(alignment: .topTrailing) {
            Button("Chiudi") { Suoni.tocco(); chiudi() }
                .tint(tinta)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Color.fondo.opacity(0.8))
                .clipShape(Capsule())
                .padding(12)
        }
        .overlay(alignment: .topLeading) {
            Text("\(indice + 1) / \(foto.count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tinta)
                .padding(.horizontal, 12).frame(height: 36)
                .background(Color.fondo.opacity(0.8))
                .clipShape(Capsule())
                .padding(12)
        }
        .task(id: indice) {
            pronta = nil
            guard foto.indices.contains(indice) else { return }
            pronta = await LibreriaLancio.daLanciare(foto[indice])
        }
    }
}

struct PaginaFotoLancio: View {
    let risorsa: PHAsset
    @State private var immagine: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let immagine {
                Image(uiImage: immagine).resizable().scaledToFit()
            } else {
                ProgressView().tint(Color.ciano)
            }
        }
        .task(id: risorsa.localIdentifier) {
            immagine = await LibreriaLancio.immagine(risorsa, lato: 2400)
        }
    }
}
#endif
