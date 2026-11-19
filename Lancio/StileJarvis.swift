import SwiftUI
import UIKit

// MARK: - I pezzi grafici di JARVIS, copiati così come sono
// Lancio nasce da solo per provarlo in fretta, ma è fatto per entrare in JARVIS: questi pezzi sono gli stessi
// di JARVIS (colori, testata HUD, pannelli, tasti alla Stark). Quando Lancio entra in JARVIS questo file si toglie
// e restano quelli originali.

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

/// Il tasto pieno di JARVIS (in JARVIS il tocco ha anche il suo suono).
struct TastoJarvis: View {
    let testo: String
    var icona = "waveform"
    let tinta: Color
    let azione: () -> Void

    var body: some View {
        Button { ApticaLancio.click(); azione() } label: {
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
