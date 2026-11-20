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
// Uno scatto del polso in avanti e la schermata vola via. Poi:
//   • se c'è uno schermo collegato in AirPlay (TV, Apple TV, Mac) → il contenuto ci atterra sopra, senza tocchi;
//   • altrimenti → si apre AirDrop con le persone vicine: se ne tocca una e a lei arriva la notifica.
// Chi riceve non deve avere niente installato. Il tocco su AirDrop Apple non lo lascia togliere a nessuna app.

extension View {
    func lanciabile(_ contenuto: ContenutoLancio?) -> some View {
        modifier(Lanciabile(contenuto: contenuto))
    }
}

struct Lanciabile: ViewModifier {
    let contenuto: ContenutoLancio?

    @ObservedObject private var schermo = SchermoLancio.condiviso
    @StateObject private var lanciatore = Lanciatore()
    @Environment(\.scenePhase) private var scena

    /// Il contenuto «in mano» adesso (il gesto legge questo, non una copia vecchia).
    @State private var inMano: ContenutoLancio?
    @State private var inVolo = false
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

    // MARK: Il piccolo segno in basso: dove andrà e quanta forza c'è

    @ViewBuilder private var segnoLancio: some View {
        if inMano != nil && !inVolo {
            HStack(spacing: 8) {
                Image(systemName: schermo.collegato ? "airplayvideo" : "wave.3.right")
                    .font(.system(size: 12, weight: .semibold))
                Text(schermo.collegato ? "SCHERMO" : "AIRDROP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
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
        if let avviso {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                Text(avviso.uppercased())
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
        }
    }

    // MARK: Il lancio

    private func arma() {
        lanciatore.armato = inMano != nil && !inVolo
    }

    private func lancia() {
        guard !inVolo, let pronto = inMano else { return }
        let versoSchermo = schermo.collegato
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
            } else {
                ConsegnaLancio.altri(pronto) { inviato in
                    if inviato {
                        Suoni.fatto()
                        mostraAvviso("Inviato con AirDrop")
                    }
                }
            }
            torna()
        }
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
