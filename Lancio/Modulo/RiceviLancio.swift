#if os(iOS)
import SwiftUI
import UIKit
import AVKit

// MARK: - .riceviLancio(): il lato di chi riceve (i tuoi dispositivi)
// Si aggiunge una volta sola, alla schermata principale (in JARVIS: alla ContentView).
// Tiene accesa la rete dei tuoi dispositivi mentre l'app è in primo piano e mostra quello che arriva:
// il link si è già aperto in Safari, il testo è negli appunti, foto e video atterrano a tutto schermo.
// Niente «Accetta»: arriva solo da dispositivi col tuo stesso Apple ID.

extension View {
    func riceviLancio() -> some View {
        modifier(RiceviLancio())
    }
}

struct RiceviLancio: ViewModifier {
    @ObservedObject private var rete = ReteLancio.condivisa
    @Environment(\.scenePhase) private var scena

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $rete.arrivo) { arrivo in
                VistaArrivoLancio(arrivo: arrivo) { rete.arrivo = nil }
            }
            .onAppear { rete.accendi() }
            .onChange(of: scena) { _, nuova in
                switch nuova {
                case .active: rete.accendi()
                case .background: rete.spegni()
                default: break
                }
            }
    }
}

// MARK: - La schermata d'arrivo

struct VistaArrivoLancio: View {
    let arrivo: ArrivoLancio
    let chiudi: () -> Void

    @State private var atterrato = false
    @State private var lettore: AVPlayer?
    private let tinta = Color.ciano

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [tinta.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ARRIVATO")
                            .font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(3)
                            .foregroundStyle(.white)
                        Text("DA \(arrivo.da.uppercased())")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                            .foregroundStyle(tinta)
                    }
                    Spacer()
                    Button("Chiudi") { Suoni.tocco(); chiudi() }.tint(tinta)
                }

                Spacer(minLength: 0)
                contenuto
                    .scaleEffect(atterrato ? 1 : 0.2)
                    .rotationEffect(.degrees(atterrato ? 0 : -14))
                    .offset(x: atterrato ? 0 : -260, y: atterrato ? 0 : 320)
                    .opacity(atterrato ? 1 : 0)
                Spacer(minLength: 0)

                azioni
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Suoni.fatto()
            withAnimation(.spring(duration: 0.65, bounce: 0.2)) { atterrato = true }
            if case .video(let url) = arrivo.cosa {
                let nuovo = AVPlayer(url: url)
                lettore = nuovo
                nuovo.play()
            }
        }
        .onDisappear { lettore?.pause() }
    }

    @ViewBuilder private var contenuto: some View {
        switch arrivo.cosa {
        case .foto(let immagine, _):
            Image(uiImage: immagine)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.35), lineWidth: 1))
                .shadow(color: tinta.opacity(0.25), radius: 30)
        case .video:
            VideoPlayer(player: lettore)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.35), lineWidth: 1))
        case .link(let url):
            Pannello(titolo: "APERTO IN SAFARI", tinta: tinta) {
                Text(url.host() ?? url.absoluteString)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(url.absoluteString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.tenue)
                    .lineLimit(3)
            }
        case .testo(let testo):
            Pannello(titolo: "NEGLI APPUNTI", tinta: tinta) {
                Text(testo)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var azioni: some View {
        switch arrivo.cosa {
        case .foto(_, let url), .video(let url):
            ShareLink(item: url) {
                Label("Salva o apri", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .foregroundStyle(Color.fondo)
                    .background(tinta)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .link(let url):
            TastoJarvis(testo: "Apri di nuovo", icona: "safari", tinta: tinta) {
                UIApplication.shared.open(url)
            }
        case .testo:
            EmptyView()
        }
    }
}
#endif
