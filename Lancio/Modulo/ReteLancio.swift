#if os(iOS)
import SwiftUI
import UIKit
import Combine
import MultipeerConnectivity

// MARK: - La rete di Lancio
// Ogni dispositivo con Lancio aperto (iPhone, iPad, Mac) si fa trovare e cerca gli altri intorno a sé.
// Usa la stessa tecnologia di AirDrop (Wi-Fi diretto e Bluetooth): funziona anche senza essere sulla stessa rete.
// Tutto viaggia cifrato.
//
// Il giro di un lancio:
//   1. chi lancia manda un invito con nome e tipo («Alessandro vuole lanciarti una foto»);
//   2. chi riceve vede «Accetta» (o accetta da solo, se quel dispositivo è tra i «fidati»);
//   3. accettato, parte il contenuto: link e testo come messaggio, la foto come file;
//   4. chi riceve lo apre (link in Safari, foto a tutto schermo, testo negli appunti) e risponde «ricevuto».

/// Un dispositivo con Lancio aperto, qui vicino.
struct VicinoLancio: Identifiable, Equatable {
    let id: String          // l'identità stabile del dispositivo (resta uguale anche se cambia nome)
    let nome: String
    let tipo: String        // «iphone», «ipad», «mac»
    let peer: MCPeerID

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
    let peer: MCPeerID
    let rispondi: (Bool, MCSession?) -> Void
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

    /// Il nome del servizio di rete: deve essere uguale a quello in Info.plist (NSBonjourServices).
    static let servizio = "lancio-jv"

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

    private var io: MCPeerID
    private var annunciatore: MCNearbyServiceAdvertiser?
    private var cercatore: MCNearbyServiceBrowser?
    private var ponte: PonteRete?
    private var sessioni: [ObjectIdentifier: MCSession] = [:]
    private var invii: [ObjectIdentifier: InvioInCorso] = [:]
    private var ricezioni: [ObjectIdentifier: String] = [:]      // sessione → nome di chi manda
    private var pulizia: Task<Void, Never>?

    private struct InvioInCorso {
        let peer: MCPeerID
        let nome: String
        let contenuto: ContenutoLancio
        var arrivato = false
    }

    private enum Chiavi {
        static let id = "lancio.id"
        static let nome = "lancio.nome"
        static let fidati = "lancio.fidati"
        static let peer = "lancio.peer"
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

        let nomeSalvato = archivio.string(forKey: Chiavi.nome)
        let nomeIniziale = ReteLancio.pulisci(nomeSalvato ?? UIDevice.current.name)
        nome = nomeIniziale
        fidati = archivio.dictionary(forKey: Chiavi.fidati) as? [String: String] ?? [:]
        io = ReteLancio.peer(per: nomeIniziale)
        // ReteLancio è unica e vive quanto l'app: si richiama direttamente, senza riferimenti deboli
        ponte = PonteRete { evento in
            Task { @MainActor in ReteLancio.condivisa.gestisci(evento) }
        }
    }

    // MARK: Accendere e spegnere

    /// Si fa trovare e cerca gli altri. Va chiamata quando l'app è in primo piano.
    func accendi() {
        guard !attiva else { return }
        let annuncio = MCNearbyServiceAdvertiser(peer: io,
                                                 discoveryInfo: ["id": idDispositivo, "tipo": tipoDispositivo],
                                                 serviceType: ReteLancio.servizio)
        annuncio.delegate = ponte
        annuncio.startAdvertisingPeer()
        annunciatore = annuncio

        let ricerca = MCNearbyServiceBrowser(peer: io, serviceType: ReteLancio.servizio)
        ricerca.delegate = ponte
        ricerca.startBrowsingForPeers()
        cercatore = ricerca
        attiva = true
    }

    /// Smette di farsi trovare (l'app va in secondo piano). I lanci in corso finiscono da soli.
    func spegni() {
        annunciatore?.stopAdvertisingPeer()
        annunciatore?.delegate = nil
        annunciatore = nil
        cercatore?.stopBrowsingForPeers()
        cercatore?.delegate = nil
        cercatore = nil
        vicini = []
        attiva = false
    }

    func cambiaNome(_ nuovo: String) {
        let pulito = ReteLancio.pulisci(nuovo)
        guard pulito != nome else { return }
        nome = pulito
        UserDefaults.standard.set(pulito, forKey: Chiavi.nome)
        UserDefaults.standard.removeObject(forKey: Chiavi.peer)
        let eraAttiva = attiva
        spegni()
        io = ReteLancio.peer(per: pulito)
        if eraAttiva { accendi() }
    }

    func dimentica(_ id: String) {
        fidati[id] = nil
        UserDefaults.standard.set(fidati, forKey: Chiavi.fidati)
    }

    // MARK: Lanciare

    func lancia(_ contenuto: ContenutoLancio, a vicino: VicinoLancio) {
        guard let cercatore else {
            mostra(.errore("La rete è spenta"))
            return
        }
        let sessione = nuovaSessione()
        let chiave = ObjectIdentifier(sessione)
        invii[chiave] = InvioInCorso(peer: vicino.peer, nome: vicino.nome, contenuto: contenuto)
        let biglietto = Biglietto(id: idDispositivo, nome: nome, cosa: contenuto.tipo)
        cercatore.invitePeer(vicino.peer, to: sessione, withContext: try? JSONEncoder().encode(biglietto), timeout: 30)
        mostra(.invito(vicino.nome))
    }

    // MARK: Ricevere

    /// La risposta all'invito: «Accetta» o «Rifiuta». Con `sempre`, quel dispositivo diventa fidato.
    func rispondi(_ accetta: Bool, sempre: Bool) {
        guard let r = richiesta else { return }
        richiesta = nil
        guard accetta else {
            r.rispondi(false, nil)
            return
        }
        if sempre {
            fidati[r.idMittente] = r.nome
            UserDefaults.standard.set(fidati, forKey: Chiavi.fidati)
        }
        accettaInvito(da: r.nome, rispondi: r.rispondi)
    }

    // MARK: Gli eventi della rete

    private func gestisci(_ evento: EventoRete) {
        switch evento {
        case .trovato(let peer, let info):
            guard let id = info?["id"], id != idDispositivo else { return }
            let vicino = VicinoLancio(id: id, nome: peer.displayName, tipo: info?["tipo"] ?? "iphone", peer: peer)
            vicini.removeAll { $0.id == id || $0.peer == peer }
            vicini.append(vicino)
            vicini.sort { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }

        case .perso(let peer):
            vicini.removeAll { $0.peer == peer }

        case .invito(let peer, let contesto, let rispondi):
            guard let contesto, let b = try? JSONDecoder().decode(Biglietto.self, from: contesto), richiesta == nil else {
                rispondi(false, nil)
                return
            }
            if fidati[b.id] != nil {
                accettaInvito(da: b.nome, rispondi: rispondi)
            } else {
                richiesta = RichiestaLancio(nome: b.nome, cosa: b.cosa, idMittente: b.id, peer: peer, rispondi: rispondi)
                ApticaLancio.click()
            }

        case .stato(let sessione, let peer, let stato):
            cambiaStato(sessione, peer: peer, stato: stato)

        case .dati(let sessione, let peer, let dati):
            ricevuti(dati, in: sessione, da: peer)

        case .file(let sessione, let peer, let url):
            fileRicevuto(url, in: sessione, da: peer)
        }
    }

    private func cambiaStato(_ sessione: MCSession, peer: MCPeerID, stato: MCSessionState) {
        let chiave = ObjectIdentifier(sessione)
        if let invio = invii[chiave] {
            switch stato {
            case .connected:
                mostra(.invio(invio.nome))
                manda(invio.contenuto, in: sessione, a: peer)
            case .notConnected:
                if !invio.arrivato { mostra(.rifiutato(invio.nome)) }
                chiudi(sessione)
            default:
                break
            }
        } else if ricezioni[chiave] != nil, stato == .notConnected {
            chiudi(sessione)
        }
    }

    private func manda(_ contenuto: ContenutoLancio, in sessione: MCSession, a peer: MCPeerID) {
        switch contenuto {
        case .link(let url):
            spedisci(Busta(tipo: "link", valore: url.absoluteString), in: sessione, a: peer)
        case .testo(let testo):
            spedisci(Busta(tipo: "testo", valore: testo), in: sessione, a: peer)
        case .foto(_, let dati):
            let file = FileManager.default.temporaryDirectory.appending(path: "lancio-\(UUID().uuidString).jpg")
            do {
                try dati.write(to: file, options: .atomic)
            } catch {
                mostra(.errore("La foto non si riesce a preparare"))
                chiudi(sessione)
                return
            }
            let chiave = ObjectIdentifier(sessione)
            _ = sessione.sendResource(at: file, withName: "foto.jpg", toPeer: peer) { @Sendable errore in
                let fallito = errore != nil
                Task { @MainActor in ReteLancio.condivisa.fotoSpedita(chiave, fallito: fallito, file: file) }
            }
        }
    }

    private func fotoSpedita(_ chiave: ObjectIdentifier, fallito: Bool, file: URL) {
        try? FileManager.default.removeItem(at: file)
        guard fallito, let invio = invii[chiave], !invio.arrivato else { return }
        mostra(.errore("La foto non è arrivata a \(invio.nome)"))
        if let sessione = sessioni[chiave] { chiudi(sessione) }
    }

    private func spedisci(_ busta: Busta, in sessione: MCSession, a peer: MCPeerID) {
        guard let dati = try? JSONEncoder().encode(busta) else { return }
        do {
            try sessione.send(dati, toPeers: [peer], with: .reliable)
        } catch {
            if let invio = invii[ObjectIdentifier(sessione)] {
                mostra(.errore("Non arriva a \(invio.nome)"))
                chiudi(sessione)
            }
        }
    }

    private func ricevuti(_ dati: Data, in sessione: MCSession, da peer: MCPeerID) {
        guard let busta = try? JSONDecoder().decode(Busta.self, from: dati) else { return }
        let chiave = ObjectIdentifier(sessione)

        // per chi lancia: la conferma che è arrivato
        if busta.tipo == "ricevuto", var invio = invii[chiave] {
            invio.arrivato = true
            invii[chiave] = invio
            Suoni.fatto()
            mostra(.consegnato(invio.nome))
            chiudiFra(sessione)
            return
        }

        // per chi riceve: link e testo
        guard let da = ricezioni[chiave] else { return }
        switch busta.tipo {
        case "link":
            guard let url = URL(string: busta.valore) else { return }
            UIApplication.shared.open(url)
            arrivo = ArrivoLancio(cosa: .link(url), da: da)
        case "testo":
            UIPasteboard.general.string = busta.valore
            arrivo = ArrivoLancio(cosa: .testo(busta.valore), da: da)
        default:
            return
        }
        conferma(in: sessione, a: peer)
    }

    private func fileRicevuto(_ url: URL?, in sessione: MCSession, da peer: MCPeerID) {
        let chiave = ObjectIdentifier(sessione)
        guard let da = ricezioni[chiave] else { return }
        guard let url, let immagine = UIImage(contentsOfFile: url.path(percentEncoded: false)) else {
            chiudi(sessione)
            return
        }
        arrivo = ArrivoLancio(cosa: .foto(immagine, url), da: da)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            // sul Mac prova ad aprirla anche in Anteprima; se il Mac non lo permette resta a tutto schermo qui
            UIApplication.shared.open(url)
        }
        conferma(in: sessione, a: peer)
    }

    private func conferma(in sessione: MCSession, a peer: MCPeerID) {
        spedisci(Busta(tipo: "ricevuto", valore: ""), in: sessione, a: peer)
        chiudiFra(sessione)
    }

    // MARK: Dettagli

    private func accettaInvito(da nome: String, rispondi: (Bool, MCSession?) -> Void) {
        let sessione = nuovaSessione()
        ricezioni[ObjectIdentifier(sessione)] = nome
        rispondi(true, sessione)
    }

    private func nuovaSessione() -> MCSession {
        let sessione = MCSession(peer: io, securityIdentity: nil, encryptionPreference: .required)
        sessione.delegate = ponte
        sessioni[ObjectIdentifier(sessione)] = sessione
        return sessione
    }

    private func chiudi(_ sessione: MCSession) {
        let chiave = ObjectIdentifier(sessione)
        sessione.delegate = nil
        sessione.disconnect()
        sessioni[chiave] = nil
        invii[chiave] = nil
        ricezioni[chiave] = nil
    }

    /// Chiude con un attimo di calma: il «ricevuto» deve fare in tempo a partire.
    private func chiudiFra(_ sessione: MCSession) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            chiudi(sessione)
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

    /// Il nome per gli altri: al massimo 40 caratteri (la rete ne accetta 63 byte), mai vuoto.
    private static func pulisci(_ nome: String) -> String {
        let pulito = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        return pulito.isEmpty ? "Lancio" : String(pulito.prefix(40))
    }

    /// L'identità di rete: si conserva tra un avvio e l'altro, così gli altri non vedono doppioni.
    private static func peer(per nome: String) -> MCPeerID {
        let archivio = UserDefaults.standard
        if let dati = archivio.data(forKey: Chiavi.peer),
           let salvato = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: dati),
           salvato.displayName == nome {
            return salvato
        }
        let nuovo = MCPeerID(displayName: nome)
        if let dati = try? NSKeyedArchiver.archivedData(withRootObject: nuovo, requiringSecureCoding: true) {
            archivio.set(dati, forKey: Chiavi.peer)
        }
        return nuovo
    }
}

// MARK: - I messaggi

/// L'invito: chi sono e cosa sto per lanciare.
nonisolated private struct Biglietto: Codable {
    let id: String
    let nome: String
    let cosa: String
}

/// Un messaggio: «link», «testo» o «ricevuto».
nonisolated private struct Busta: Codable {
    let tipo: String
    let valore: String
}

// MARK: - Il ponte con la rete
// MultipeerConnectivity chiama da un suo filo, non dal principale: il ponte raccoglie le chiamate
// e le passa a ReteLancio sul filo principale. Il file ricevuto si sposta subito, perché iOS lo cancella
// appena la chiamata finisce.

nonisolated enum EventoRete: @unchecked Sendable {
    case trovato(MCPeerID, [String: String]?)
    case perso(MCPeerID)
    case invito(MCPeerID, Data?, (Bool, MCSession?) -> Void)
    case stato(MCSession, MCPeerID, MCSessionState)
    case dati(MCSession, MCPeerID, Data)
    case file(MCSession, MCPeerID, URL?)
}

nonisolated final class PonteRete: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private let avvisa: @Sendable (EventoRete) -> Void

    init(avvisa: @escaping @Sendable (EventoRete) -> Void) {
        self.avvisa = avvisa
    }

    // sessione
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        avvisa(.stato(session, peerID, state))
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        avvisa(.dati(session, peerID, data))
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: Error?) {
        var salvato: URL?
        if let localURL, error == nil {
            let cartella = URL.documentsDirectory.appending(path: "Ricevuti", directoryHint: .isDirectory)
            let destinazione = cartella.appending(path: "Lancio \(UUID().uuidString.prefix(8)).jpg")
            do {
                try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: localURL, to: destinazione)
                salvato = destinazione
            } catch {
                salvato = nil
            }
        }
        avvisa(.file(session, peerID, salvato))
    }

    // farsi trovare
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        avvisa(.invito(peerID, context, invitationHandler))
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}

    // cercare
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        avvisa(.trovato(peerID, info))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        avvisa(.perso(peerID))
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}
#endif
