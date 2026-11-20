#if os(iOS)
import SwiftUI
import UIKit

// MARK: - .lanciabile(…): rende lanciabile qualsiasi schermata
// Si aggiunge alla vista che mostra la cosa da lanciare (una foto aperta, una pagina web):
//
//     fotoAperta.lanciabile(.foto(immagine, jpeg))
//     browser.lanciabile(pagina.url.map { .link($0) })
//
// Con uno scatto del polso (o il tasto) la schermata vola via e il contenuto parte:
//   • un solo dispositivo vicino con Lancio aperto → va lì, senza chiedere niente;
//   • più dispositivi → compare la lista, se ne tocca uno;
//   • nessuno → si apre AirDrop (per i Mac e gli iPhone che non hanno Lancio).
// Se l'iPhone è collegato in AirPlay a un Mac o a una TV, anche quello schermo è tra le destinazioni.

extension View {
    func lanciabile(_ contenuto: ContenutoLancio?) -> some View {
        modifier(Lanciabile(contenuto: contenuto))
    }
}

struct Lanciabile: ViewModifier {
    let contenuto: ContenutoLancio?

    @ObservedObject private var rete = ReteLancio.condivisa
    @ObservedObject private var schermo = SchermoLancio.condiviso
    @StateObject private var lanciatore = Lanciatore()
    @Environment(\.scenePhase) private var scena

    /// Il contenuto «in mano» adesso (il gesto legge questo, non una copia vecchia).
    @State private var inMano: ContenutoLancio?
    @State private var inVolo = false
    @State private var scelta = false
    @State private var avviso: String?

    private let tinta = Color.ciano

    private enum Destinazione: Identifiable {
        case vicino(VicinoLancio)
        case schermo

        var id: String {
            switch self {
            case .vicino(let v): return v.id
            case .schermo: return "schermo"
            }
        }
        var nome: String {
            switch self {
            case .vicino(let v): return v.nome
            case .schermo: return "Schermo AirPlay"
            }
        }
        var icona: String {
            switch self {
            case .vicino(let v): return v.icona
            case .schermo: return "airplayvideo"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: inVolo ? -1000 : 0)
            .scaleEffect(inVolo ? 0.5 : 1)
            .rotationEffect(.degrees(inVolo ? -8 : 0))
            .opacity(inVolo ? 0 : 1)
            .safeAreaInset(edge: .bottom, spacing: 0) { barra }
            .overlay(alignment: .top) { striscia }
            .overlay { if scelta { sceltaDestinazione } }
            .onAppear {
                inMano = contenuto
                lanciatore.alLancio = { lancia() }
                lanciatore.accendi()
                arma()
            }
            .onDisappear { lanciatore.spegni() }
            .onChange(of: contenuto?.chiave) { _, _ in
                inMano = contenuto
                arma()
            }
            .onChange(of: scena) { _, nuova in
                if nuova == .active { lanciatore.accendi() } else { lanciatore.spegni() }
            }
    }

    // MARK: Le destinazioni

    private var destinazioni: [Destinazione] {
        var tutte = rete.vicini.map { Destinazione.vicino($0) }
        if schermo.collegato { tutte.append(.schermo) }
        return tutte
    }

    /// Dove andrà il prossimo lancio, scritto in una parola.
    private var verso: String {
        let d = destinazioni
        switch d.count {
        case 0: return "AIRDROP"
        case 1: return d[0].nome.uppercased()
        default: return "\(d.count) VICINI"
        }
    }

    // MARK: La barra in basso

    private var barra: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: destinazioni.count == 1 ? destinazioni[0].icona : "dot.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                Text(verso)
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(lanciatore.disponibile ? "\(Int(lanciatore.forza * 100))%" : "")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tinta)
            HStack(spacing: 10) {
                if lanciatore.disponibile {
                    HStack(spacing: 2) {
                        ForEach(0..<16, id: \.self) { k in
                            Rectangle()
                                .fill(tinta.opacity(Double(k) < lanciatore.forza * 16 ? 1 : 0.18))
                                .frame(maxWidth: .infinity).frame(height: 8)
                        }
                    }
                }
                Button { Suoni.tocco(); lancia() } label: {
                    Label("Lancia", systemImage: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 16).frame(height: 40)
                        .frame(maxWidth: lanciatore.disponibile ? nil : .infinity)
                        .foregroundStyle(Color.fondo)
                        .background(tinta)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: tinta.opacity(0.4), radius: 8)
                }
                .buttonStyle(StileStark())
                .disabled(inMano == nil || inVolo)
                .opacity(inMano == nil ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.fondo.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(tinta.opacity(0.22)).frame(height: 1) }
    }

    // MARK: Lo stato del lancio, in alto

    @ViewBuilder private var striscia: some View {
        if let testo = testoStriscia {
            HStack(spacing: 8) {
                if attende {
                    ProgressView().tint(tinta).controlSize(.small)
                } else {
                    Image(systemName: iconaStriscia)
                }
                Text(testo.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5)
                    .lineLimit(1)
            }
            .foregroundStyle(tinta)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Color.fondo.opacity(0.92))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tinta.opacity(0.35), lineWidth: 1))
            .shadow(color: tinta.opacity(0.3), radius: 10)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.35, bounce: 0.25), value: testo)
        }
    }

    private var testoStriscia: String? {
        if let avviso { return avviso }
        switch rete.invio {
        case .fermo: return nil
        case .invito(let nome): return "In attesa di \(nome)"
        case .invio(let nome): return "In volo verso \(nome)"
        case .consegnato(let nome): return "Arrivato su \(nome)"
        case .rifiutato(let nome): return "\(nome) non ha accettato"
        case .errore(let testo): return testo
        }
    }

    private var attende: Bool {
        switch rete.invio {
        case .invito, .invio: return avviso == nil
        default: return false
        }
    }

    private var iconaStriscia: String {
        switch rete.invio {
        case .consegnato: return "checkmark"
        case .rifiutato, .errore: return "xmark"
        default: return "paperplane"
        }
    }

    // MARK: La scelta, quando i vicini sono più d'uno

    private var sceltaDestinazione: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { annullaScelta() }
            Pannello(titolo: "DOVE", tinta: tinta) {
                ForEach(destinazioni) { d in
                    Button {
                        Suoni.tocco()
                        scelta = false
                        if let inMano { invia(inMano, a: d) }
                        torna()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: d.icona).font(.system(size: 18)).frame(width: 28)
                            Text(d.nome).font(.system(size: 15, weight: .semibold, design: .monospaced))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(tinta)
                        .padding(.horizontal, 12).frame(height: 48)
                        .background(tinta.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(StileStark())
                }
                Button {
                    Suoni.tocco()
                    scelta = false
                    if let inMano { airDrop(inMano) }
                    torna()
                } label: {
                    Label("AirDrop", systemImage: "wave.3.right")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.tenue)
                        .frame(maxWidth: .infinity).frame(height: 40)
                }
                Button("Annulla") { Suoni.tocco(); annullaScelta() }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tint(tinta)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    // MARK: Il lancio

    private func arma() {
        lanciatore.armato = inMano != nil && !inVolo && !scelta
    }

    private func lancia() {
        guard !inVolo, !scelta else { return }
        guard let pronto = inMano else {
            Suoni.errore()
            return
        }
        let dove = destinazioni
        Suoni.chatSvuota()
        ApticaLancio.lancio()
        withAnimation(.timingCurve(0.4, 0, 0.9, 0.6, duration: 0.42)) { inVolo = true }
        arma()
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            switch dove.count {
            case 0:
                airDrop(pronto)
                torna()
            case 1:
                invia(pronto, a: dove[0])
                torna()
            default:
                withAnimation(.easeOut(duration: 0.2)) { scelta = true }
            }
        }
    }

    private func invia(_ contenuto: ContenutoLancio, a destinazione: Destinazione) {
        switch destinazione {
        case .vicino(let v):
            rete.lancia(contenuto, a: v)
        case .schermo:
            schermo.mostra(contenuto)
            Suoni.fatto()
            mostraAvviso("Sullo schermo AirPlay")
        }
    }

    private func airDrop(_ contenuto: ContenutoLancio) {
        ConsegnaLancio.altri(contenuto) { inviato in
            if inviato {
                Suoni.fatto()
                mostraAvviso("Inviato con AirDrop")
            }
        }
    }

    private func annullaScelta() {
        withAnimation(.easeOut(duration: 0.2)) { scelta = false }
        torna()
    }

    /// La schermata torna al suo posto, pronta per un altro lancio.
    private func torna() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { inVolo = false }
            arma()
        }
    }

    private func mostraAvviso(_ testo: String) {
        withAnimation { avviso = testo }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { avviso = nil }
        }
    }
}
#endif
