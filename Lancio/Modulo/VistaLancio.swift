#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Banco di prova del gesto
// Questa schermata serve solo per provare il lancio prima di metterlo in JARVIS: in JARVIS non c'è un'app «Lancio»,
// il gesto si aggiunge alle sue schermate (foto aperta, video, Browser) con `.lanciabile(…)`.
// FOTO: apri una foto e lanciala. WEB: apri una pagina e lanciala.

struct VistaLancio: View {
    var chiudi: (() -> Void)? = nil

    private enum Sezione: String, CaseIterable, Identifiable {
        case foto = "Foto", web = "Web"
        var id: String { rawValue }
        var icona: String {
            switch self {
            case .foto: return "photo.on.rectangle"
            case .web: return "globe"
            }
        }
    }

    @ObservedObject private var schermo = SchermoLancio.condiviso
    @StateObject private var libreria = LibreriaLancio()
    @StateObject private var pagina = PaginaWebLancio()
    @State private var sezione: Sezione = .foto
    @State private var fotoAperta: Int?

    private let tinta = Color.ciano

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [tinta.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                testata
                Group {
                    switch sezione {
                    case .foto: VistaFotoLancio(libreria: libreria) { indice in apriFoto(indice) }
                    case .web: VistaWebLancio(pagina: pagina)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                barraSezioni
            }

            if let fotoAperta {
                VistaFotoApertaLancio(foto: libreria.foto, indice: fotoAperta) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) { self.fotoAperta = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .aperturaHUD("Lancio")
    }

    // MARK: Pezzi

    private var testata: some View {
        HStack(alignment: .top) {
            TestataScheda(titolo: "Lancio", sottotitolo: schermo.collegato ? "verso lo schermo airplay" : "verso airdrop",
                          icona: "paperplane", tinta: tinta)
            if let chiudi {
                Button("Chiudi") { Suoni.tocco(); chiudi() }.tint(tinta)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var barraSezioni: some View {
        HStack(spacing: 6) {
            ForEach(Sezione.allCases) { voce in
                let acceso = voce == sezione
                Button {
                    Suoni.tocco()
                    withAnimation(.snappy(duration: 0.22)) { sezione = voce }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: voce.icona).font(.system(size: 16, weight: .medium))
                        Text(voce.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .foregroundStyle(acceso ? Color.fondo : tinta)
                    .background(acceso ? tinta : tinta.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(acceso ? 0 : 0.22), lineWidth: 1))
                }
                .buttonStyle(StileStark())
                .accessibilityAddTraits(acceso ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
    }

    private func apriFoto(_ indice: Int) {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { fotoAperta = indice }
    }
}

#Preview {
    VistaLancio()
}
#endif
