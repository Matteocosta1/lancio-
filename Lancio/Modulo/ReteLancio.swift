#if os(iOS)
import SwiftUI
import UIKit
import Combine
import Network
import CryptoKit

// MARK: - La rete dei tuoi dispositivi
// Jarvis parla con Jarvis, ma solo tra i TUOI dispositivi (stesso Apple ID): iPhone, iPad, Mac.
// Si trovano da soli con Bonjour, anche senza la stessa Wi-Fi (Wi-Fi diretto, come AirDrop).
//
// Come si riconoscono: la prima volta Jarvis crea una chiave segreta e la mette in iCloud (archivio chiave-valore),
// che la porta su tutti i dispositivi col tuo Apple ID. Ogni dispositivo si presenta con un'impronta della chiave
// e vede solo chi ha la stessa; tutto quello che passa è cifrato con quella chiave (ChaCha20-Poly1305).
// Per questo non serve nessun «Accetta»: un dispositivo che non è tuo non vede niente e non può mandare niente.
//
// Il giro: chi lancia si collega e manda il contenuto (link, testo, foto, video a pezzi);
// chi riceve lo apre (link in Safari, foto e video a tutto schermo, testo negli appunti) e risponde «ricevuto».

/// Un tuo dispositivo con Jarvis aperto, qui vicino.
struct VicinoLancio: Identifiable, Equatable {
    let id: String
    let nome: String
    let tipo: String        // «iphone», «ipad», «mac»
    let indirizzo: NWEndpoint

    var icona: String {
        switch tipo {
        case "mac": return "laptopcomputer"
        case "ipad": return "ipad"
        default: return "iphone"
        }
    }
}

/// Quello che è arrivato.
struct ArrivoLancio: Identifiable {
    enum Cosa {
        case foto(UIImage, URL)
        case video(URL)
        case link(URL)
        case testo(String)
    }
    let id = UUID()
    let cosa: Cosa
    let da: String
}

/// A che punto è il lancio verso un tuo dispositivo.
enum StatoInvio: Equatable {
    case fermo
    case invio(String)
    case consegnato(String)
    case errore(String)
}

final class ReteLancio: ObservableObject {
    static let condivisa = ReteLancio()

    /// Il tipo di servizio Bonjour: deve essere uguale a quello in Info.plist (NSBonjourServices).
    nonisolated static let tipoServizio = "_lancio-jv._tcp"

    @Published private(set) var vicini: [VicinoLancio] = []
    @Published private(set) var attiva = false
    @Published private(set) var invio: StatoInvio = .fermo
    @Published var arrivo: ArrivoLancio?

    let idDispositivo: String
    let tipoDispositivo: String
    let nome: String

    private let coda = DispatchQueue(label: "lancio.rete")
    private var chiave: SymmetricKey
    private var ascolto: NWListener?
    private var ricerca: NWBrowser?
    private var voluta = false
    private var canali: [ObjectIdentifier: CanaleLancio] = [:]
    private var invii: [ObjectIdentifier: InvioInCorso] = [:]
    private var videoInArrivo: [ObjectIdentifier: VideoInArrivo] = [:]
    private var pulizia: Task<Void, Never>?
    private var osservatore: NSObjectProtocol?

    private struct InvioInCorso {
        let nome: String
        let contenuto: ContenutoLancio
        var arrivato = false
    }

    private final class VideoInArrivo {
        let file: URL
        let scrittura: FileHandle
        init(file: URL, scrittura: FileHandle) {
            self.file = file
            self.scrittura = scrittura
        }
    }

    private enum Chiavi {
        static let id = "lancio.id"
        static let famiglia = "lancio.famiglia"
    }

    private init() {
        let archivio = UserDefaults.standard
        let id = archivio.string(forKey: Chiavi.id) ?? UUID().uuidString
        archivio.set(id, forKey: Chiavi.id)
        idDispositivo = id

        if ProcessInfo.processInfo.isiOSAppOnMac {
            tipoDispositivo = "mac"
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            tipoDispositivo = "ipad"
        } else {
            tipoDispositivo = "iphone"
        }
        let nomeDispositivo = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        nome = nomeDispositivo.isEmpty ? "Jarvis" : String(nomeDispositivo.prefix(40))

        chiave = ReteLancio.chiaveFamiglia()
        // se iCloud porta una chiave diversa (creata prima su un altro tuo dispositivo), si usa quella
        osservatore = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main) { _ in
                MainActor.assumeIsolated { ReteLancio.condivisa.chiaveCambiata() }
            }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    // MARK: Accendere e spegnere

    /// Si fa trovare dai tuoi dispositivi e li cerca. Va chiamata quando l'app è in primo piano.
    func accendi() {
        voluta = true
        guard !attiva else { return }

        do {
            let nuovoAscolto = try NWListener(using: ReteLancio.parametri())
            nuovoAscolto.service = servizio()
            nuovoAscolto.newConnectionHandler = { @Sendable connessione in
                let canale = CanaleLancio(connessione)
                Task { @MainActor in ReteLancio.condivisa.nuovoCanale(canale) }
            }
            nuovoAscolto.stateUpdateHandler = { @Sendable stato in
                if case .failed = stato {
                    Task { @MainActor in ReteLancio.condivisa.riavvia() }
                }
            }
            nuovoAscolto.start(queue: coda)
            ascolto = nuovoAscolto
        } catch {
            ascolto = nil
        }

        let nuovaRicerca = NWBrowser(for: .bonjourWithTXTRecord(type: ReteLancio.tipoServizio, domain: nil),
                                     using: ReteLancio.parametri())
        nuovaRicerca.browseResultsChangedHandler = { @Sendable risultati, _ in
            let trovati = risultati.compactMap { VicinoGrezzo(da: $0) }
            Task { @MainActor in ReteLancio.condivisa.aggiornaVicini(trovati) }
        }
        nuovaRicerca.stateUpdateHandler = { @Sendable stato in
            if case .failed = stato {
                Task { @MainActor in ReteLancio.condivisa.riavvia() }
            }
        }
        nuovaRicerca.start(queue: coda)
        ricerca = nuovaRicerca
        attiva = true
    }

    /// Smette di farsi trovare (l'app va in secondo piano). I lanci in corso finiscono da soli.
    func spegni() {
        voluta = false
        ferma()
    }

    // MARK: Lanciare

    func lancia(_ contenuto: ContenutoLancio, a vicino: VicinoLancio) {
        let canale = CanaleLancio(verso: vicino.indirizzo)
        canale.chiave = chiave
        let chiaveCanale = ObjectIdentifier(canale)
        canali[chiaveCanale] = canale
        invii[chiaveCanale] = InvioInCorso(nome: vicino.nome, contenuto: contenuto)
        collega(canale)
        canale.alPronto = { @Sendable in
            Task { @MainActor in ReteLancio.condivisa.canalePronto(chiaveCanale) }
        }
        canale.avvia()
        mostra(.invio(vicino.nome))
    }

    // MARK: Gli eventi della rete

    private func aggiornaVicini(_ trovati: [VicinoGrezzo]) {
        let mio = impronta()
        var visti: [String: VicinoLancio] = [:]
        for grezzo in trovati where grezzo.id != idDispositivo && grezzo.gruppo == mio {
            visti[grezzo.id] = VicinoLancio(id: grezzo.id, nome: grezzo.nome, tipo: grezzo.tipo, indirizzo: grezzo.indirizzo)
        }
        vicini = visti.values.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    /// Un tuo dispositivo si è collegato: si aspetta quello che manda.
    private func nuovoCanale(_ canale: CanaleLancio) {
        canale.chiave = chiave
        canali[ObjectIdentifier(canale)] = canale
        collega(canale)
        canale.avvia()
    }

    private func collega(_ canale: CanaleLancio) {
        let chiaveCanale = ObjectIdentifier(canale)
        canale.allArrivo = { @Sendable messaggio in
            Task { @MainActor in ReteLancio.condivisa.messaggio(messaggio, da: chiaveCanale) }
        }
        canale.allaFine = { @Sendable in
            Task { @MainActor in ReteLancio.condivisa.canaleChiuso(chiaveCanale) }
        }
    }

    /// Chi lancia: il collegamento è pronto, parte il contenuto.
    private func canalePronto(_ chiaveCanale: ObjectIdentifier) {
        guard let canale = canali[chiaveCanale], let invio = invii[chiaveCanale] else { return }
        let da = nome
        switch invio.contenuto {
        case .link(let url):
            canale.manda(MessaggioLancio(tipo: "link", nome: da, valore: url.absoluteString))
        case .testo(let testo):
            canale.manda(MessaggioLancio(tipo: "testo", nome: da, valore: testo))
        case .foto(_, let dati):
            canale.manda(MessaggioLancio(tipo: "foto", nome: da, dati: dati))
        case .video(let url):
            canale.mandaVideo(url, da: da) { @Sendable riuscito in
                guard !riuscito else { return }
                Task { @MainActor in ReteLancio.condivisa.invioFallito(chiaveCanale) }
            }
        }
    }

    private func messaggio(_ m: MessaggioLancio, da chiaveCanale: ObjectIdentifier) {
        guard let canale = canali[chiaveCanale] else { return }

        // per chi lancia: la conferma
        if var invio = invii[chiaveCanale] {
            guard m.tipo == "ricevuto" else { return }
            invio.arrivato = true
            invii[chiaveCanale] = invio
            Suoni.fatto()
            mostra(.consegnato(invio.nome))
            chiudiFra(chiaveCanale)
            return
        }

        // per chi riceve
        let da = m.nome ?? "un tuo dispositivo"
        switch m.tipo {
        case "link":
            guard let valore = m.valore, let url = URL(string: valore) else { return }
            UIApplication.shared.open(url)
            arrivo = ArrivoLancio(cosa: .link(url), da: da)
            conferma(canale, chiaveCanale)
        case "testo":
            guard let valore = m.valore else { return }
            UIPasteboard.general.string = valore
            arrivo = ArrivoLancio(cosa: .testo(valore), da: da)
            conferma(canale, chiaveCanale)
        case "foto":
            guard let dati = m.dati, let immagine = UIImage(data: dati),
                  let file = ReteLancio.salva(dati, estensione: "jpg") else { return }
            arrivo = ArrivoLancio(cosa: .foto(immagine, file), da: da)
            apriSulMac(file)
            conferma(canale, chiaveCanale)
        case "video-inizio":
            let estensione = (m.valore ?? "mov").isEmpty ? "mov" : (m.valore ?? "mov")
            let file = FileManager.default.temporaryDirectory.appending(path: "lancio-\(UUID().uuidString).\(estensione)")
            guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil),
                  let scrittura = try? FileHandle(forWritingTo: file) else { return }
            videoInArrivo[chiaveCanale] = VideoInArrivo(file: file, scrittura: scrittura)
        case "video-pezzo":
            guard let video = videoInArrivo[chiaveCanale], let dati = m.dati else { return }
            try? video.scrittura.write(contentsOf: dati)
        case "video-fine":
            guard let video = videoInArrivo[chiaveCanale] else { return }
            videoInArrivo[chiaveCanale] = nil
            try? video.scrittura.close()
            guard let file = ReteLancio.sposta(video.file) else { return }
            arrivo = ArrivoLancio(cosa: .video(file), da: da)
            apriSulMac(file)
            conferma(canale, chiaveCanale)
        default:
            break
        }
    }

    private func canaleChiuso(_ chiaveCanale: ObjectIdentifier) {
        if let invio = invii[chiaveCanale], !invio.arrivato {
            mostra(.errore("Non arrivato su \(invio.nome)"))
        }
        if let video = videoInArrivo[chiaveCanale] {
            try? video.scrittura.close()
            try? FileManager.default.removeItem(at: video.file)
        }
        dimenticaCanale(chiaveCanale)
    }

    private func invioFallito(_ chiaveCanale: ObjectIdentifier) {
        guard let invio = invii[chiaveCanale], !invio.arrivato else { return }
        mostra(.errore("Il video non è arrivato su \(invio.nome)"))
        chiudi(chiaveCanale)
    }

    // MARK: Dettagli

    private func conferma(_ canale: CanaleLancio, _ chiaveCanale: ObjectIdentifier) {
        canale.manda(MessaggioLancio(tipo: "ricevuto"))
        chiudiFra(chiaveCanale)
    }

    /// Sul Mac prova ad aprire il file anche nell'app del Mac (Anteprima, QuickTime);
    /// se il Mac non lo permette, resta a tutto schermo in Jarvis.
    private func apriSulMac(_ file: URL) {
        guard ProcessInfo.processInfo.isiOSAppOnMac else { return }
        UIApplication.shared.open(file)
    }

    private static func cartellaRicevuti() -> URL? {
        let cartella = URL.documentsDirectory.appending(path: "Ricevuti", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
            return cartella
        } catch {
            return nil
        }
    }

    private static func salva(_ dati: Data, estensione: String) -> URL? {
        guard let cartella = cartellaRicevuti() else { return nil }
        let file = cartella.appending(path: "Lancio \(UUID().uuidString.prefix(8)).\(estensione)")
        do {
            try dati.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    private static func sposta(_ temporaneo: URL) -> URL? {
        guard let cartella = cartellaRicevuti() else { return nil }
        let file = cartella.appending(path: "Lancio \(UUID().uuidString.prefix(8)).\(temporaneo.pathExtension)")
        do {
            try FileManager.default.moveItem(at: temporaneo, to: file)
            return file
        } catch {
            return nil
        }
    }

    private func chiudi(_ chiaveCanale: ObjectIdentifier) {
        canali[chiaveCanale]?.chiudi()
        dimenticaCanale(chiaveCanale)
    }

    private func dimenticaCanale(_ chiaveCanale: ObjectIdentifier) {
        canali[chiaveCanale] = nil
        invii[chiaveCanale] = nil
        videoInArrivo[chiaveCanale] = nil
    }

    /// Chiude con un attimo di calma: l'ultimo messaggio deve fare in tempo a partire.
    private func chiudiFra(_ chiaveCanale: ObjectIdentifier) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            chiudi(chiaveCanale)
        }
    }

    /// Mostra lo stato del lancio; quelli finali spariscono da soli dopo qualche secondo.
    private func mostra(_ stato: StatoInvio) {
        invio = stato
        pulizia?.cancel()
        switch stato {
        case .consegnato, .errore:
            pulizia = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                invio = .fermo
            }
        default:
            break
        }
    }

    // MARK: La rete

    private func ferma() {
        ascolto?.cancel()
        ascolto = nil
        ricerca?.cancel()
        ricerca = nil
        vicini = []
        attiva = false
    }

    /// Se la rete cade (es. il Wi-Fi si spegne e si riaccende), si riparte da capo.
    private func riavvia() {
        ferma()
        guard voluta else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if voluta { accendi() }
        }
    }

    private func servizio() -> NWListener.Service {
        NWListener.Service(name: idDispositivo, type: ReteLancio.tipoServizio, domain: nil,
                           txtRecord: NWTXTRecord(["nome": nome, "tipo": tipoDispositivo, "gruppo": impronta()]))
    }

    /// L'impronta della chiave: dice «sono della stessa famiglia» senza svelare la chiave.
    private func impronta() -> String {
        let digest = chiave.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// La chiave arrivata da iCloud è diversa da quella in uso: si riparte con quella.
    private func chiaveCambiata() {
        let nuova = ReteLancio.chiaveFamiglia()
        let vecchia = chiave.withUnsafeBytes { Data($0) }
        let arrivata = nuova.withUnsafeBytes { Data($0) }
        guard vecchia != arrivata else { return }
        chiave = nuova
        if attiva {
            ferma()
            if voluta { accendi() }
        }
    }

    /// La chiave dei tuoi dispositivi, in iCloud. La prima volta si crea e si mette lì.
    private static func chiaveFamiglia() -> SymmetricKey {
        let archivio = NSUbiquitousKeyValueStore.default
        if let dati = archivio.data(forKey: Chiavi.famiglia), dati.count == 32 {
            return SymmetricKey(data: dati)
        }
        let nuova = SymmetricKey(size: .bits256)
        archivio.set(nuova.withUnsafeBytes { Data($0) }, forKey: Chiavi.famiglia)
        archivio.synchronize()
        return nuova
    }

    /// TCP con il Wi-Fi diretto acceso (peer-to-peer), come AirDrop.
    nonisolated static func parametri() -> NWParameters {
        let parametri = NWParameters.tcp
        parametri.includePeerToPeer = true
        return parametri
    }
}

// MARK: - Quello che arriva dalla ricerca

/// Un risultato di Bonjour, già letto dal record TXT.
nonisolated struct VicinoGrezzo: @unchecked Sendable {
    let id: String
    let nome: String
    let tipo: String
    let gruppo: String
    let indirizzo: NWEndpoint

    init?(da risultato: NWBrowser.Result) {
        guard case .service(let nomeServizio, _, _, _) = risultato.endpoint else { return nil }
        var record: NWTXTRecord?
        if case .bonjour(let txt) = risultato.metadata { record = txt }
        id = nomeServizio
        nome = record?["nome"] ?? nomeServizio
        tipo = record?["tipo"] ?? "iphone"
        gruppo = record?["gruppo"] ?? ""
        indirizzo = risultato.endpoint
    }
}

// MARK: - I messaggi

/// Un messaggio: «link», «testo», «foto», «video-inizio», «video-pezzo», «video-fine», «ricevuto».
nonisolated struct MessaggioLancio: Codable, Sendable {
    var tipo: String
    var nome: String?
    var valore: String?
    var dati: Data?

    init(tipo: String, nome: String? = nil, valore: String? = nil, dati: Data? = nil) {
        self.tipo = tipo
        self.nome = nome
        self.valore = valore
        self.dati = dati
    }
}

// MARK: - Un collegamento

/// Un collegamento con un tuo dispositivo. I messaggi viaggiano in pacchi: 4 byte di lunghezza, poi il contenuto
/// cifrato con la chiave dei tuoi dispositivi. Un pacco che non si decifra chiude il collegamento.
nonisolated final class CanaleLancio: @unchecked Sendable {
    var alPronto: (@Sendable () -> Void)?
    var allArrivo: (@Sendable (MessaggioLancio) -> Void)?
    var allaFine: (@Sendable () -> Void)?
    var chiave: SymmetricKey?

    private let connessione: NWConnection
    private let coda = DispatchQueue(label: "lancio.canale")
    private var finito = false
    private static let massimo: UInt32 = 60_000_000          // un pacco non supera 60 MB
    private static let pezzo = 1_000_000                      // il video viaggia a pezzi da 1 MB

    init(_ connessione: NWConnection) {
        self.connessione = connessione
    }

    convenience init(verso indirizzo: NWEndpoint) {
        self.init(NWConnection(to: indirizzo, using: ReteLancio.parametri()))
    }

    func avvia() {
        connessione.stateUpdateHandler = { [weak self] stato in
            guard let self else { return }
            switch stato {
            case .ready:
                self.alPronto?()
                self.leggi()
            case .failed, .cancelled:
                self.termina()
            default:
                break
            }
        }
        connessione.start(queue: coda)
    }

    func manda(_ messaggio: MessaggioLancio, fatto: (@Sendable (Bool) -> Void)? = nil) {
        guard let pacco = impacchetta(messaggio) else {
            fatto?(false)
            return
        }
        connessione.send(content: pacco, completion: .contentProcessed { errore in
            fatto?(errore == nil)
        })
    }

    /// Il video a pezzi: un pezzo parte solo quando il precedente è uscito, così la memoria resta bassa.
    func mandaVideo(_ file: URL, da nome: String, fine: @escaping @Sendable (Bool) -> Void) {
        coda.async {
            guard let lettura = try? FileHandle(forReadingFrom: file) else {
                fine(false)
                return
            }
            let lettore = Lettore(lettura)
            self.manda(MessaggioLancio(tipo: "video-inizio", nome: nome, valore: file.pathExtension)) { riuscito in
                guard riuscito else { lettore.chiudi(); fine(false); return }
                self.prossimoPezzo(lettore, nome: nome, fine: fine)
            }
        }
    }

    private func prossimoPezzo(_ lettore: Lettore, nome: String, fine: @escaping @Sendable (Bool) -> Void) {
        guard let dati = lettore.leggi(CanaleLancio.pezzo), !dati.isEmpty else {
            lettore.chiudi()
            manda(MessaggioLancio(tipo: "video-fine", nome: nome)) { riuscito in fine(riuscito) }
            return
        }
        manda(MessaggioLancio(tipo: "video-pezzo", dati: dati)) { [weak self] riuscito in
            guard riuscito, let self else { lettore.chiudi(); fine(false); return }
            self.coda.async { self.prossimoPezzo(lettore, nome: nome, fine: fine) }
        }
    }

    func chiudi() {
        connessione.cancel()
    }

    private func impacchetta(_ messaggio: MessaggioLancio) -> Data? {
        guard let chiave, let chiaro = try? JSONEncoder().encode(messaggio),
              let cifrato = try? ChaChaPoly.seal(chiaro, using: chiave).combined else { return nil }
        var pacco = withUnsafeBytes(of: UInt32(cifrato.count).bigEndian) { Data($0) }
        pacco.append(cifrato)
        return pacco
    }

    private func leggi() {
        connessione.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] testa, _, completo, errore in
            guard let self else { return }
            guard errore == nil, let testa, testa.count == 4 else {
                if completo || errore != nil { self.chiudi() }
                return
            }
            let lunghezza = testa.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard lunghezza > 0, lunghezza <= CanaleLancio.massimo else {
                self.chiudi()
                return
            }
            let quanti = Int(lunghezza)
            self.connessione.receive(minimumIncompleteLength: quanti, maximumLength: quanti) { corpo, _, _, errore in
                guard errore == nil, let corpo, corpo.count == quanti, let chiave = self.chiave,
                      let scatola = try? ChaChaPoly.SealedBox(combined: corpo),
                      let chiaro = try? ChaChaPoly.open(scatola, using: chiave),
                      let messaggio = try? JSONDecoder().decode(MessaggioLancio.self, from: chiaro) else {
                    self.chiudi()
                    return
                }
                self.allArrivo?(messaggio)
                self.leggi()
            }
        }
    }

    /// Avvisa una volta sola che il collegamento è finito.
    private func termina() {
        guard !finito else { return }
        finito = true
        allaFine?()
    }
}

/// Legge un file a pezzi, sul filo del collegamento.
nonisolated final class Lettore: @unchecked Sendable {
    private let lettura: FileHandle

    init(_ lettura: FileHandle) {
        self.lettura = lettura
    }

    func leggi(_ quanti: Int) -> Data? {
        try? lettura.read(upToCount: quanti)
    }

    func chiudi() {
        try? lettura.close()
    }
}
#endif
