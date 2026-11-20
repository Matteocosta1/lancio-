#if os(iOS)
import SwiftUI
import UIKit
import Combine
import Network
import CryptoKit

// MARK: - La rete di Lancio
// Ogni dispositivo con Lancio aperto (iPhone, iPad, Mac) si fa trovare e cerca gli altri intorno a sé con Bonjour.
// Il collegamento è diretto (Wi-Fi peer-to-peer, la stessa via di AirDrop): funziona anche senza essere sulla
// stessa rete Wi-Fi. Ogni messaggio viaggia cifrato (ChaCha20-Poly1305).
//
// Il giro di un lancio:
//   1. chi lancia si collega e manda un invito con nome e tipo («Alessandro vuole lanciarti una foto»);
//   2. chi riceve vede «Accetta» (o accetta da solo, se quel dispositivo è tra i «fidati») e risponde sì o no;
//   3. con il sì parte il contenuto (link, testo o foto);
//   4. chi riceve lo apre (link in Safari, foto a tutto schermo, testo negli appunti) e risponde «ricevuto».

/// Un dispositivo con Lancio aperto, qui vicino.
struct VicinoLancio: Identifiable, Equatable {
    let id: String          // l'identità stabile del dispositivo (resta uguale anche se cambia nome)
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

/// Qualcuno vuole lanciarci qualcosa: aspetta «Accetta» o «Rifiuta».
struct RichiestaLancio: Identifiable {
    let id = UUID()
    let nome: String
    let cosa: String
    let idMittente: String
    let canale: CanaleLancio
}

/// Quello che è arrivato.
struct ArrivoLancio: Identifiable {
    enum Cosa {
        case foto(UIImage, URL)
        case link(URL)
        case testo(String)
    }
    let id = UUID()
    let cosa: Cosa
    let da: String
}

/// A che punto è il lancio, per chi lancia.
enum StatoInvio: Equatable {
    case fermo
    case invito(String)         // aspetta che l'altro accetti
    case invio(String)          // accettato: sta mandando
    case consegnato(String)
    case rifiutato(String)
    case errore(String)
}

final class ReteLancio: ObservableObject {
    static let condivisa = ReteLancio()

    /// Il tipo di servizio Bonjour: deve essere uguale a quello in Info.plist (NSBonjourServices).
    nonisolated static let tipoServizio = "_lancio-jv._tcp"

    @Published private(set) var vicini: [VicinoLancio] = []
    @Published private(set) var attiva = false
    @Published private(set) var invio: StatoInvio = .fermo
    @Published var richiesta: RichiestaLancio?
    @Published var arrivo: ArrivoLancio?
    /// I dispositivi da cui si accetta senza chiedere: id → nome.
    @Published private(set) var fidati: [String: String]
    /// Il nome con cui questo dispositivo si fa vedere dagli altri.
    @Published private(set) var nome: String

    let idDispositivo: String
    let tipoDispositivo: String

    private let coda = DispatchQueue(label: "lancio.rete")
    private var ascolto: NWListener?
    private var ricerca: NWBrowser?
    private var voluta = false                                 // l'app vuole la rete accesa (è in primo piano)
    private var canali: [ObjectIdentifier: CanaleLancio] = [:]
    private var invii: [ObjectIdentifier: InvioInCorso] = [:]
    private var ricezioni: [ObjectIdentifier: String] = [:]     // canale → nome di chi manda
    private var accettati: Set<ObjectIdentifier> = []
    private var pulizia: Task<Void, Never>?

    private struct InvioInCorso {
        let nome: String
        let contenuto: ContenutoLancio
        var accettato = false
        var arrivato = false
    }

    private enum Chiavi {
        static let id = "lancio.id"
        static let nome = "lancio.nome"
        static let fidati = "lancio.fidati"
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

        nome = ReteLancio.pulisci(archivio.string(forKey: Chiavi.nome) ?? UIDevice.current.name)
        fidati = archivio.dictionary(forKey: Chiavi.fidati) as? [String: String] ?? [:]
    }

    // MARK: Accendere e spegnere

    /// Si fa trovare e cerca gli altri. Va chiamata quando l'app è in primo piano.
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

    func cambiaNome(_ nuovo: String) {
        let pulito = ReteLancio.pulisci(nuovo)
        guard pulito != nome else { return }
        nome = pulito
        UserDefaults.standard.set(pulito, forKey: Chiavi.nome)
        ascolto?.service = servizio()            // si ripresenta agli altri col nome nuovo
    }

    func dimentica(_ id: String) {
        fidati[id] = nil
        UserDefaults.standard.set(fidati, forKey: Chiavi.fidati)
    }

    // MARK: Lanciare

    func lancia(_ contenuto: ContenutoLancio, a vicino: VicinoLancio) {
        let canale = CanaleLancio(verso: vicino.indirizzo)
        let chiave = ObjectIdentifier(canale)
        canali[chiave] = canale
        invii[chiave] = InvioInCorso(nome: vicino.nome, contenuto: contenuto)
        collega(canale)
        canale.alPronto = { @Sendable in
            Task { @MainActor in ReteLancio.condivisa.canalePronto(chiave) }
        }
        canale.avvia()
        mostra(.invito(vicino.nome))

        // se l'altro non risponde entro 40 secondi, si lascia perdere
        Task {
            try? await Task.sleep(for: .seconds(40))
            guard let invio = invii[chiave], !invio.accettato else { return }
            mostra(.rifiutato(invio.nome))
            chiudi(chiave)
        }
    }

    // MARK: Ricevere

    /// La risposta all'invito: «Accetta» o «Rifiuta». Con `sempre`, quel dispositivo diventa fidato.
    func rispondi(_ accetta: Bool, sempre: Bool) {
        guard let r = richiesta else { return }
        richiesta = nil
        let chiave = ObjectIdentifier(r.canale)
        guard accetta else {
            r.canale.manda(MessaggioLancio(tipo: "no"))
            chiudiFra(chiave)
            return
        }
        if sempre {
            fidati[r.idMittente] = r.nome
            UserDefaults.standard.set(fidati, forKey: Chiavi.fidati)
        }
        accettaCanale(chiave)
    }

    // MARK: Gli eventi della rete

    private func aggiornaVicini(_ trovati: [VicinoGrezzo]) {
        var visti: [String: VicinoLancio] = [:]
        for grezzo in trovati where grezzo.id != idDispositivo {
            visti[grezzo.id] = VicinoLancio(id: grezzo.id, nome: grezzo.nome, tipo: grezzo.tipo, indirizzo: grezzo.indirizzo)
        }
        vicini = visti.values.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    /// Qualcuno si è collegato a noi: si aspetta il suo invito.
    private func nuovoCanale(_ canale: CanaleLancio) {
        let chiave = ObjectIdentifier(canale)
        canali[chiave] = canale
        collega(canale)
        canale.avvia()
    }

    private func collega(_ canale: CanaleLancio) {
        let chiave = ObjectIdentifier(canale)
        canale.allArrivo = { @Sendable messaggio in
            Task { @MainActor in ReteLancio.condivisa.messaggio(messaggio, da: chiave) }
        }
        canale.allaFine = { @Sendable in
            Task { @MainActor in ReteLancio.condivisa.canaleChiuso(chiave) }
        }
    }

    /// Chi lancia: il collegamento è pronto, parte l'invito.
    private func canalePronto(_ chiave: ObjectIdentifier) {
        guard let canale = canali[chiave], let invio = invii[chiave] else { return }
        canale.manda(MessaggioLancio(tipo: "invito", id: idDispositivo, nome: nome, cosa: invio.contenuto.tipo))
    }

    private func messaggio(_ m: MessaggioLancio, da chiave: ObjectIdentifier) {
        guard let canale = canali[chiave] else { return }

        // per chi lancia
        if var invio = invii[chiave] {
            switch m.tipo {
            case "si":
                invio.accettato = true
                invii[chiave] = invio
                mostra(.invio(invio.nome))
                manda(invio.contenuto, su: canale)
            case "no":
                mostra(.rifiutato(invio.nome))
                chiudi(chiave)
            case "ricevuto":
                invio.arrivato = true
                invii[chiave] = invio
                Suoni.fatto()
                mostra(.consegnato(invio.nome))
                chiudiFra(chiave)
            default:
                break
            }
            return
        }

        // per chi riceve
        switch m.tipo {
        case "invito":
            guard let id = m.id, let chi = m.nome, richiesta == nil else {
                canale.manda(MessaggioLancio(tipo: "no"))
                chiudiFra(chiave)
                return
            }
            ricezioni[chiave] = chi
            if fidati[id] != nil {
                accettaCanale(chiave)
            } else {
                richiesta = RichiestaLancio(nome: chi, cosa: m.cosa ?? "testo", idMittente: id, canale: canale)
                ApticaLancio.click()
            }

        case "link", "testo", "foto":
            guard accettati.contains(chiave), let da = ricezioni[chiave] else { return }
            ricevi(m, da: da)
            canale.manda(MessaggioLancio(tipo: "ricevuto"))
            chiudiFra(chiave)

        default:
            break
        }
    }

    private func canaleChiuso(_ chiave: ObjectIdentifier) {
        if let invio = invii[chiave], !invio.arrivato {
            switch self.invio {
            case .invito, .invio: mostra(.errore("Collegamento con \(invio.nome) perso"))
            default: break
            }
        }
        if let r = richiesta, ObjectIdentifier(r.canale) == chiave {
            richiesta = nil
        }
        dimenticaCanale(chiave)
    }

    // MARK: Dettagli del lancio

    private func manda(_ contenuto: ContenutoLancio, su canale: CanaleLancio) {
        switch contenuto {
        case .link(let url):
            canale.manda(MessaggioLancio(tipo: "link", valore: url.absoluteString))
        case .testo(let testo):
            canale.manda(MessaggioLancio(tipo: "testo", valore: testo))
        case .foto(_, let dati):
            canale.manda(MessaggioLancio(tipo: "foto", dati: dati))
        }
    }

    private func ricevi(_ m: MessaggioLancio, da: String) {
        switch m.tipo {
        case "link":
            guard let valore = m.valore, let url = URL(string: valore) else { return }
            UIApplication.shared.open(url)
            arrivo = ArrivoLancio(cosa: .link(url), da: da)
        case "testo":
            guard let valore = m.valore else { return }
            UIPasteboard.general.string = valore
            arrivo = ArrivoLancio(cosa: .testo(valore), da: da)
        case "foto":
            guard let dati = m.dati, let immagine = UIImage(data: dati) else { return }
            let cartella = URL.documentsDirectory.appending(path: "Ricevuti", directoryHint: .isDirectory)
            let file = cartella.appending(path: "Lancio \(UUID().uuidString.prefix(8)).jpg")
            do {
                try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
                try dati.write(to: file, options: .atomic)
            } catch {
                return
            }
            arrivo = ArrivoLancio(cosa: .foto(immagine, file), da: da)
            if ProcessInfo.processInfo.isiOSAppOnMac {
                // sul Mac prova ad aprirla anche in Anteprima; se il Mac non lo permette resta a tutto schermo qui
                UIApplication.shared.open(file)
            }
        default:
            break
        }
    }

    private func accettaCanale(_ chiave: ObjectIdentifier) {
        guard let canale = canali[chiave] else { return }
        accettati.insert(chiave)
        canale.manda(MessaggioLancio(tipo: "si"))
    }

    private func chiudi(_ chiave: ObjectIdentifier) {
        canali[chiave]?.chiudi()
        dimenticaCanale(chiave)
    }

    private func dimenticaCanale(_ chiave: ObjectIdentifier) {
        canali[chiave] = nil
        invii[chiave] = nil
        ricezioni[chiave] = nil
        accettati.remove(chiave)
    }

    /// Chiude con un attimo di calma: l'ultimo messaggio deve fare in tempo a partire.
    private func chiudiFra(_ chiave: ObjectIdentifier) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            chiudi(chiave)
        }
    }

    /// Mostra lo stato del lancio; quelli finali spariscono da soli dopo qualche secondo.
    private func mostra(_ stato: StatoInvio) {
        invio = stato
        pulizia?.cancel()
        switch stato {
        case .consegnato, .rifiutato, .errore:
            pulizia = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                invio = .fermo
            }
        default:
            break
        }
    }

    // MARK: Dettagli della rete

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
                           txtRecord: NWTXTRecord(["nome": nome, "tipo": tipoDispositivo]))
    }

    /// TCP con il Wi-Fi diretto acceso (peer-to-peer), come AirDrop.
    nonisolated static func parametri() -> NWParameters {
        let parametri = NWParameters.tcp
        parametri.includePeerToPeer = true
        return parametri
    }

    /// Il nome per gli altri: al massimo 40 caratteri, mai vuoto.
    private static func pulisci(_ nome: String) -> String {
        let pulito = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return pulito.isEmpty ? "Lancio" : String(pulito.prefix(40))
    }
}

// MARK: - Quello che arriva dalla ricerca

/// Un risultato di Bonjour, già letto: id, nome e tipo dal record TXT.
nonisolated struct VicinoGrezzo: @unchecked Sendable {
    let id: String
    let nome: String
    let tipo: String
    let indirizzo: NWEndpoint

    init?(da risultato: NWBrowser.Result) {
        guard case .service(let nomeServizio, _, _, _) = risultato.endpoint else { return nil }
        var record: NWTXTRecord?
        if case .bonjour(let txt) = risultato.metadata { record = txt }
        id = nomeServizio
        nome = record?["nome"] ?? nomeServizio
        tipo = record?["tipo"] ?? "iphone"
        indirizzo = risultato.endpoint
    }
}

// MARK: - I messaggi

/// Un messaggio di Lancio: «invito», «si», «no», «link», «testo», «foto», «ricevuto».
nonisolated struct MessaggioLancio: Codable, Sendable {
    var tipo: String
    var id: String?
    var nome: String?
    var cosa: String?
    var valore: String?
    var dati: Data?

    init(tipo: String, id: String? = nil, nome: String? = nil, cosa: String? = nil, valore: String? = nil, dati: Data? = nil) {
        self.tipo = tipo
        self.id = id
        self.nome = nome
        self.cosa = cosa
        self.valore = valore
        self.dati = dati
    }
}

/// La cifratura dei messaggi: ChaCha20-Poly1305 con una chiave comune a tutti i Lancio.
/// Protegge da chi «ascolta» la rete; chi può ricevere lo decide sempre «Accetta».
nonisolated enum CifraLancio {
    static let chiave = SymmetricKey(data: SHA256.hash(data: Data("Lancio · JARVIS · chiave di rete v1".utf8)))

    static func chiudi(_ dati: Data) throws -> Data {
        try ChaChaPoly.seal(dati, using: chiave).combined
    }

    static func apri(_ dati: Data) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: dati), using: chiave)
    }
}

// MARK: - Un collegamento

/// Un collegamento con un altro dispositivo. I messaggi viaggiano in pacchi: 4 byte di lunghezza, poi il contenuto cifrato.
/// Lavora su un suo filo; avvisa con `alPronto`, `allArrivo` e `allaFine`.
nonisolated final class CanaleLancio: @unchecked Sendable {
    var alPronto: (@Sendable () -> Void)?
    var allArrivo: (@Sendable (MessaggioLancio) -> Void)?
    var allaFine: (@Sendable () -> Void)?

    private let connessione: NWConnection
    private let coda = DispatchQueue(label: "lancio.canale")
    private var finito = false
    private static let massimo: UInt32 = 60_000_000          // un pacco non supera 60 MB

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

    func manda(_ messaggio: MessaggioLancio) {
        guard let chiaro = try? JSONEncoder().encode(messaggio), let cifrato = try? CifraLancio.chiudi(chiaro) else { return }
        var pacco = withUnsafeBytes(of: UInt32(cifrato.count).bigEndian) { Data($0) }
        pacco.append(cifrato)
        connessione.send(content: pacco, completion: .contentProcessed { _ in })
    }

    func chiudi() {
        connessione.cancel()
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
                guard errore == nil, let corpo, corpo.count == quanti,
                      let chiaro = try? CifraLancio.apri(corpo),
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
#endif
