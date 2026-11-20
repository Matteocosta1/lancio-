#if os(iOS)
import SwiftUI
import UIKit

// MARK: - .lanciabile(…): il gesto del lancio su qualsiasi schermata di JARVIS
// Si aggiunge alla vista che mostra la cosa da lanciare: una foto aperta, un video, una pagina web, un testo.
//
//     fotoAperta.lanciabile(.foto(immagine, jpeg))
//     video.lanciabile(.video(url))
//     browser.lanciabile(paginaAttuale.map { .link($0) })
//
// Uno scatto del polso in avanti e la schermata vola via. Poi, in quest'ordine:
//   1. schermo collegato in AirPlay (TV, Apple TV, Mac) → ci atterra sopra, senza tocchi;
//   2. un tuo dispositivo con Jarvis aperto qui vicino (stesso Apple ID) → arriva lì, senza tocchi
//      (se sono più d'uno, compare la lista e se ne tocca uno);
//   3. nessuno dei due → si apre AirDrop con le persone vicine: se ne tocca una e le arriva la notifica.
// Chi riceve con AirDrop non deve avere niente installato. Quel tocco Apple non lo lascia togliere a nessuna app.

extension View {
    func lanciabile(_ contenuto: ContenutoLancio?) -> some View {
        modifier(Lanciabile(contenuto: contenuto))
    }
}

struct Lanciabile: ViewModifier {
    let contenuto: ContenutoLancio?

    @ObservedObject private var schermo = SchermoLancio.condiviso
    @ObservedObject private var rete = ReteLancio.condivisa
    @StateObject private var lanciatore = Lanciatore()
    @Environment(\.scenePhase) private var scena

    /// Il contenuto «in mano» adesso (il gesto legge questo, non una copia vecchia).
    @State private var inMano: ContenutoLancio?
    @State private var inVolo = false
    @State private var scelta = false
    @State private var avviso: String?

    private let tinta = Color.ciano

    func body(content: Content) -> some View {
        content
            .offset(y: inVolo ? -1000 : 0)
            .scaleEffect(inVolo ? 0.5 : 1)
            .rotationEffect(.degrees(inVolo ? -8 : 0))
            .opacity(inVolo ? 0 : 1)
            .overlay(alignment: .top) { striscia }
            .overlay(alignment: .bottomTrailing) { segnoLancio }
            .overlay { if scelta { sceltaDispositivo } }
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

    // MARK: Dove andrà

    private var verso: (icona: String, testo: String) {
        if schermo.collegato { return (icona: "airplayvideo", testo: "SCHERMO") }
        switch rete.vicini.count {
        case 0: return (icona: "wave.3.right", testo: "AIRDROP")
        case 1: return (icona: rete.vicini[0].icona, testo: rete.vicini[0].nome.uppercased())
        default: return (icona: "dot.radiowaves.left.and.right", testo: "\(rete.vicini.count) TUOI")
        }
    }

    // MARK: Il piccolo segno in basso: dove andrà e quanta forza c'è

    @ViewBuilder private var segnoLancio: some View {
        if inMano != nil && !inVolo {
            HStack(spacing: 8) {
                Image(systemName: verso.icona)
                    .font(.system(size: 12, weight: .semibold))
                Text(verso.testo)
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
                    .lineLimit(1)
                if lanciatore.disponibile {
                    HStack(spacing: 2) {
                        ForEach(0..<8, id: \.self) { k in
                            Rectangle()
                                .fill(tinta.opacity(Double(k) < lanciatore.forza * 8 ? 1 : 0.2))
                                .frame(width: 4, height: 8)
                        }
                    }
                }
            }
            .foregroundStyle(tinta)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Color.fondo.opacity(0.85))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tinta.opacity(0.3), lineWidth: 1))
            .padding(12)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // MARK: L'esito, in alto

    @ViewBuilder private var striscia: some View {
        if let testo = testoStriscia {
            HStack(spacing: 8) {
                if inCorso {
                    ProgressView().tint(tinta).controlSize(.small)
                } else {
                    Image(systemName: errore ? "xmark" : "checkmark")
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
        case .invio(let nome): return "In volo verso \(nome)"
        case .consegnato(let nome): return "Arrivato su \(nome)"
        case .errore(let testo): return testo
        }
    }

    private var inCorso: Bool {
        if avviso != nil { return false }
        if case .invio = rete.invio { return true }
        return false
    }

    private var errore: Bool {
        if avviso != nil { return false }
        if case .errore = rete.invio { return true }
        return false
    }

    // MARK: La scelta, quando i tuoi dispositivi vicini sono più d'uno

    private var sceltaDispositivo: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { annullaScelta() }
            Pannello(titolo: "DOVE", tinta: tinta) {
                ForEach(rete.vicini) { vicino in
                    Button {
                        Suoni.tocco()
                        scelta = false
                        if let inMano { rete.lancia(inMano, a: vicino) }
                        torna()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: vicino.icona).font(.system(size: 18)).frame(width: 28)
                            Text(vicino.nome).font(.system(size: 15, weight: .semibold, design: .monospaced))
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
        guard !inVolo, !scelta, let pronto = inMano else { return }
        let versoSchermo = schermo.collegato
        let tuoi = rete.vicini
        Suoni.chatSvuota()
        ApticaLancio.lancio()
        withAnimation(.timingCurve(0.4, 0, 0.9, 0.6, duration: 0.42)) { inVolo = true }
        arma()
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            if versoSchermo {
                schermo.mostra(pronto)
                Suoni.fatto()
                mostraAvviso("Sullo schermo")
                torna()
            } else if tuoi.count == 1 {
                rete.lancia(pronto, a: tuoi[0])
                torna()
            } else if tuoi.count > 1 {
                withAnimation(.easeOut(duration: 0.2)) { scelta = true }
            } else {
                airDrop(pronto)
                torna()
            }
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
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { avviso = testo }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { avviso = nil }
        }
    }
}
#endif
