#if os(iOS)
import SwiftUI
import UIKit

// MARK: - .riceviLancio(): il lato di chi riceve
// Si aggiunge una volta sola, alla schermata principale dell'app (in JARVIS: alla ContentView).
// Tiene accesa la rete mentre l'app è in primo piano, mostra «Accetta / Rifiuta» quando qualcuno lancia,
// e la schermata d'arrivo con quello che è atterrato (il link si è già aperto in Safari, il testo è negli appunti).

extension View {
    func riceviLancio() -> some View {
        modifier(RiceviLancio())
    }
}

struct RiceviLancio: ViewModifier {
    @ObservedObject private var rete = ReteLancio.condivisa
    @Environment(\.scenePhase) private var scena
    @State private var sempre = false

    private let tinta = Color.ciano

    func body(content: Content) -> some View {
        content
            .overlay {
                if let richiesta = rete.richiesta {
                    riquadroRichiesta(richiesta)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.2), value: rete.richiesta?.id)
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

    private func riquadroRichiesta(_ r: RichiestaLancio) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                TestataScheda(titolo: "Lancio", sottotitolo: "in arrivo", icona: "paperplane", tinta: tinta)
                Text(r.nome)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("vuole lanciarti \(articolo(r.cosa)).")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Color.tenue)
                Toggle(isOn: $sempre) {
                    Text("Sempre da questo dispositivo")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tinta)
                }
                .tint(tinta)
                HStack(spacing: 10) {
                    Button {
                        Suoni.tocco()
                        rete.rispondi(false, sempre: false)
                        sempre = false
                    } label: {
                        Text("Rifiuta")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .foregroundStyle(tinta)
                            .background(tinta.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(StileStark())
                    TastoJarvis(testo: "Accetta", icona: "checkmark", tinta: tinta) {
                        rete.rispondi(true, sempre: sempre)
                        sempre = false
                    }
                }
            }
            .padding(18)
            .background(Color.fondo)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(tinta.opacity(0.35), lineWidth: 1))
            .shadow(color: tinta.opacity(0.25), radius: 24)
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
        }
    }

    private func articolo(_ cosa: String) -> String {
        switch cosa {
        case "foto": return "una foto"
        case "link": return "un link"
        default: return "un testo"
        }
    }
}

// MARK: - La schermata d'arrivo

struct VistaArrivoLancio: View {
    let arrivo: ArrivoLancio
    let chiudi: () -> Void

    @State private var atterrato = false
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
        }
    }

    @ViewBuilder private var contenuto: some View {
        switch arrivo.cosa {
        case .foto(let immagine, _):
            Image(uiImage: immagine)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.35), lineWidth: 1))
                .shadow(color: tinta.opacity(0.25), radius: 30)
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
        case .foto(_, let url):
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
