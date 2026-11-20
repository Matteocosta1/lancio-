#if os(iOS)
import SwiftUI
import UIKit
import Combine
import AVKit

// MARK: - SCHERMO: il Mac collegato in AirPlay
// Quando l'iPhone si collega al Mac (Centro di Controllo › Duplica schermo › il Mac), iOS offre all'app uno «schermo
// esterno». Lancio ci disegna la sua schermata HUD: in attesa, e il contenuto che atterra quando lo lanci.
// È solo da vedere: il file resta sull'iPhone.

final class SchermoLancio: ObservableObject {
    static let condiviso = SchermoLancio()

    /// Il Mac (o un altro schermo) è collegato in AirPlay.
    @Published private(set) var collegato = false
    /// L'ultimo contenuto lanciato sullo schermo.
    @Published private(set) var arrivo: ContenutoLancio?
    /// Cresce a ogni lancio: fa ripartire l'animazione d'atterraggio anche se il contenuto è lo stesso.
    @Published private(set) var numero = 0

    func mostra(_ contenuto: ContenutoLancio) {
        arrivo = contenuto
        numero += 1
    }

    func collega() { collegato = true }

    func scollega() {
        collegato = false
        arrivo = nil
    }

    /// Da chiamare nel delegato dell'app, in `application(_:configurationForConnecting:options:)`:
    /// per lo schermo esterno torna la scena di Lancio, per tutto il resto `nil` (resta com'è).
    static func configurazione(per sessione: UISceneSession) -> UISceneConfiguration? {
        guard sessione.role == .windowExternalDisplayNonInteractive else { return nil }
        let configurazione = UISceneConfiguration(name: "Schermo Lancio", sessionRole: sessione.role)
        configurazione.delegateClass = SchermoLancioDelegato.self
        return configurazione
    }
}

/// La scena dello schermo esterno: una finestra con la schermata HUD di Lancio.
final class SchermoLancioDelegato: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scena = scene as? UIWindowScene else { return }
        let finestra = UIWindow(windowScene: scena)
        finestra.rootViewController = UIHostingController(rootView: VistaSchermoLancio(schermo: .condiviso))
        finestra.isHidden = false
        window = finestra
        SchermoLancio.condiviso.collega()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        SchermoLancio.condiviso.scollega()
        window = nil
    }
}

// MARK: - La schermata sul Mac

struct VistaSchermoLancio: View {
    @ObservedObject var schermo: SchermoLancio
    @State private var gira = false
    private let tinta = Color.ciano

    var body: some View {
        GeometryReader { g in
            let lato = min(g.size.width, g.size.height)
            ZStack {
                Color.fondo
                RadialGradient(colors: [tinta.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: lato * 0.7)
                angoli(g.size)
                VStack {
                    HStack {
                        Text("JARVIS · LANCIO").foregroundStyle(tinta)
                        Spacer()
                        Text("AIRPLAY").foregroundStyle(Color.tenue)
                    }
                    .font(.system(size: lato * 0.022, weight: .semibold, design: .monospaced)).tracking(3)
                    Spacer()
                    Text(schermo.arrivo == nil ? "" : "SOLO DA VEDERE · RESTA SULL'IPHONE")
                        .font(.system(size: lato * 0.02, weight: .semibold, design: .monospaced)).tracking(3)
                        .foregroundStyle(Color.tenue)
                }
                .padding(lato * 0.09)

                if let arrivo = schermo.arrivo {
                    contenuto(arrivo, lato: lato)
                        .id(schermo.numero)
                        .transition(.asymmetric(insertion: .modifier(active: Atterraggio(fase: 0), identity: Atterraggio(fase: 1)),
                                                removal: .opacity))
                } else {
                    attesa(lato: lato)
                        .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.65, bounce: 0.2), value: schermo.numero)
        }
        .ignoresSafeArea()
        .onAppear { gira = true }
    }

    /// Gli angoli del mirino, come nel caricamento di JARVIS.
    private func angoli(_ size: CGSize) -> some View {
        let margine = min(size.width, size.height) * 0.05
        let l = min(size.width, size.height) * 0.07
        return Path { p in
            let w = size.width - 2 * margine, h = size.height - 2 * margine
            for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                p.move(to: CGPoint(x: margine + x, y: margine + y + dy * l))
                p.addLine(to: CGPoint(x: margine + x, y: margine + y))
                p.addLine(to: CGPoint(x: margine + x + dx * l, y: margine + y))
            }
        }
        .stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func attesa(lato: CGFloat) -> some View {
        VStack(spacing: lato * 0.04) {
            ZStack {
                Circle().stroke(tinta.opacity(0.2), lineWidth: 1)
                Circle().trim(from: 0, to: 0.3).stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(gira ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: gira)
            }
            .frame(width: lato * 0.2, height: lato * 0.2)
            .shadow(color: tinta.opacity(0.5), radius: 12)
            Text("IN ATTESA DI LANCIO")
                .font(.system(size: lato * 0.025, weight: .semibold, design: .monospaced)).tracking(4)
                .foregroundStyle(tinta)
        }
    }

    @ViewBuilder private func contenuto(_ arrivo: ContenutoLancio, lato: CGFloat) -> some View {
        Group {
            switch arrivo {
            case .foto(let immagine, _):
                Image(uiImage: immagine)
                    .resizable().scaledToFit()
                    .frame(maxWidth: lato * 1.1, maxHeight: lato * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .video(let url):
                VideoSchermoLancio(url: url)
                    .frame(maxWidth: lato * 1.4, maxHeight: lato * 0.7)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .link(let url):
                VStack(alignment: .leading, spacing: lato * 0.02) {
                    Text(url.host() ?? url.absoluteString)
                        .font(.system(size: lato * 0.05, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    Text(url.absoluteString)
                        .font(.system(size: lato * 0.024, design: .monospaced)).foregroundStyle(tinta)
                        .lineLimit(2)
                }
                .frame(maxWidth: lato * 1.0, alignment: .leading)
                .padding(lato * 0.04)
            case .testo(let testo):
                Text(testo)
                    .font(.system(size: lato * 0.045))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: lato * 1.0, alignment: .leading)
                    .padding(lato * 0.04)
            }
        }
        .padding(12)
        .background(tinta.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tinta.opacity(0.35), lineWidth: 1))
        .shadow(color: tinta.opacity(0.25), radius: 30)
    }
}

/// Il video lanciato sullo schermo: parte da solo, col suo audio.
private struct VideoSchermoLancio: View {
    let url: URL
    @State private var lettore: AVPlayer?

    var body: some View {
        VideoPlayer(player: lettore)
            .onAppear {
                let nuovo = AVPlayer(url: url)
                lettore = nuovo
                nuovo.play()
            }
            .onDisappear { lettore?.pause() }
    }
}

/// L'atterraggio: arriva dal basso a sinistra (da dove sta l'iPhone), ruotato e piccolo, e si posa al centro.
private struct Atterraggio: ViewModifier {
    let fase: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.2 + 0.8 * fase)
            .rotationEffect(.degrees(-14 * (1 - fase)))
            .offset(x: -460 * (1 - fase), y: 300 * (1 - fase))
            .opacity(fase)
    }
}
#endif
