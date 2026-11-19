import SwiftUI
import UIKit

// MARK: - I pezzi grafici di JARVIS, copiati così come sono (solo per l'app Lancio da sola)
// Colori, testata HUD, pannelli, tasti alla Stark, caricamento HUD: gli stessi di JARVIS.
// In JARVIS questa cartella (SoloApp) NON si copia: lì ci sono già gli originali.

extension Color {
    static let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
    static let ciano2 = Color(red: 0.04, green: 0.65, blue: 0.79)
    static let fondo = Color(red: 0.02, green: 0.03, blue: 0.04)
    static let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)
}

/// Tasti alla Stark: si schiacciano, si illuminano e tornano su con una molla.
struct StileStark: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? 0.25 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

/// La testata: icona dentro un anello che gira, nome della scheda in grande, una riga di stato.
struct TestataScheda: View {
    let titolo: String
    let sottotitolo: String
    let icona: String
    let tinta: Color
    @State private var gira = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tinta.opacity(0.25), lineWidth: 1)
                Circle().trim(from: 0, to: 0.3).stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(gira ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: gira)
                Image(systemName: icona)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(tinta)
            }
            .frame(width: 52, height: 52)
            .shadow(color: tinta.opacity(0.5), radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(titolo.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .monospaced)).tracking(3)
                    .foregroundStyle(.white)
                Text(sottotitolo.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(tinta)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
        .onAppear { gira = true }
    }
}

/// Un riquadro con bordo sottile del colore della scheda.
struct Pannello<Contenuto: View>: View {
    var titolo: String? = nil
    let tinta: Color
    @ViewBuilder let contenuto: () -> Contenuto

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let titolo {
                Text(titolo).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            }
            contenuto()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinta.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tinta.opacity(0.22), lineWidth: 1))
    }
}

/// Il tasto per passare la parola a JARVIS.
struct TastoJarvis: View {
    let testo: String
    var icona = "waveform"
    let tinta: Color
    let azione: () -> Void

    var body: some View {
        Button { Suoni.tocco(); azione() } label: {
            Label(testo, systemImage: icona)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(Color.fondo)
                .background(tinta)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: tinta.opacity(0.4), radius: 8)
        }
        .buttonStyle(StileStark())
    }
}

/// Il caricamento da HUD: gli angoli del mirino, dentro gli anelli che girano in senso opposto con la riga di scansione,
/// sotto la barra a segmenti con la percentuale e le voci dei «sistemi» che si accendono una alla volta.
struct CaricamentoHUD: View {
    let titolo: String
    let tinta: Color
    private let sistemi = ["COLLEGAMENTO AL CERVELLO", "LETTURA SENSORI", "ANALISI", "COMPILAZIONE SCHEDA"]
    @State private var inizio = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let passato = ctx.date.timeIntervalSince(inizio)
            let avanzamento = min(0.92, 1 - exp(-passato / 1.6))          // sale svelto, poi aspetta i dati
            let voce = min(sistemi.count - 1, Int(avanzamento * Double(sistemi.count) / 0.92))
            VStack(spacing: 18) {
                ZStack {
                    // gli angoli del mirino
                    Path { p in
                        let l: CGFloat = 26, w: CGFloat = 200, h: CGFloat = 160
                        for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                            p.move(to: CGPoint(x: x, y: y + dy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
                        }
                    }
                    .stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 200, height: 160)
                    // gli anelli
                    Circle().stroke(tinta.opacity(0.15), lineWidth: 1).frame(width: 110, height: 110)
                    Circle().trim(from: 0, to: 0.28).stroke(tinta, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 110, height: 110).rotationEffect(.radians(t * 2.2))
                    Circle().trim(from: 0, to: 0.18).stroke(tinta.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 84, height: 84).rotationEffect(.radians(-t * 3.1))
                    Circle().trim(from: 0, to: 0.5).stroke(tinta.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        .frame(width: 60, height: 60).rotationEffect(.radians(t * 1.4))
                    Text(titolo.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                        .foregroundStyle(tinta)
                    // riga di scansione
                    Rectangle().fill(tinta.opacity(0.5)).frame(width: 110, height: 1.5)
                        .offset(y: CGFloat(sin(t * 2.4)) * 53)
                        .mask(Circle().frame(width: 110, height: 110))
                }
                .shadow(color: tinta.opacity(0.5), radius: 14)
                // la barra a segmenti con la percentuale
                VStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(0..<24, id: \.self) { k in
                            Rectangle().fill(tinta.opacity(Double(k) < avanzamento * 24 ? 1 : 0.18)).frame(width: 7, height: 8)
                        }
                    }
                    Text("\(Int(avanzamento * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(tinta)
                        .contentTransition(.numericText())
                }
                // i sistemi
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(sistemi.enumerated()), id: \.offset) { k, s in
                        let acceso = k <= voce
                        HStack(spacing: 8) {
                            Rectangle().fill(tinta.opacity(acceso ? 1 : 0.2)).frame(width: 6, height: 6)
                            Text(s).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                                .foregroundStyle(tinta.opacity(acceso ? 0.95 : 0.3))
                            if k == voce {
                                Text(String(repeating: "▪", count: Int(t * 6) % 4)).font(.system(size: 8)).foregroundStyle(tinta)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { inizio = Date() }
    }
}

/// L'apertura da HUD per le sezioni che non caricano dati dal cervello (Sentinella, Wiretap, Interprete, Allenatore, Browser…)
/// e per quelle che hanno già la loro pagina (Vitals, Ricordi, Confidente): un attimo di caricamento con i suoni, poi la sezione.
struct AperturaHUD: ViewModifier {
    let titolo: String
    var durata = 1.1
    @State private var coperto = true

    func body(content: Content) -> some View {
        content
            .overlay {
                if coperto {
                    ZStack {
                        Color.fondo.ignoresSafeArea()
                        CaricamentoHUD(titolo: titolo, tinta: .ciano)
                    }
                    .transition(.opacity)
                }
            }
            .onAppear { Suoni.schedaApre() }
            .task {
                try? await Task.sleep(for: .seconds(durata))
                Suoni.schedaPronta()
                withAnimation(.easeOut(duration: 0.4)) { coperto = false }
            }
    }
}

extension View {
    /// Apre la sezione con il caricamento HUD di JARVIS.
    func aperturaHUD(_ titolo: String) -> some View {
        modifier(AperturaHUD(titolo: titolo))
    }
}
