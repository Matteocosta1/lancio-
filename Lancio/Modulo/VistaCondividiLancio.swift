#if os(iOS)
import SwiftUI
import UIKit
import Combine

// MARK: - LANCIA dal tasto Condividi
// Sei in Foto o in Safari, tocchi Condividi › Lancia: si apre questa scheda con la foto o il link già in mano.
// Uno scatto del polso (o trascini in su, o il tasto) e arriva sul tuo Mac: la foto in Anteprima, il link in Safari.
// Da qui solo «Mio»: AirDrop per gli altri è già nel foglio di iOS, e lo schermo AirPlay lo usa solo l'app.

/// Quello che il tasto Condividi ha passato: si riempie appena iOS lo consegna.
final class StatoCondividiLancio: ObservableObject {
    @Published private(set) var contenuto: ContenutoLancio?
    @Published private(set) var leggendo = true
    @Published private(set) var problema: String?

    func arrivaFoto(_ jpeg: Data?) {
        if let jpeg, let immagine = UIImage(data: jpeg) {
            contenuto = .foto(immagine, jpeg)
        } else {
            problema = "Questa foto non si riesce ad aprire."
        }
        leggendo = false
    }

    func arrivaLink(_ url: URL?) {
        if let url, !url.isFileURL {
            contenuto = .link(url)
        } else {
            problema = "Questo link non si riesce a leggere."
        }
        leggendo = false
    }

    func arrivaTesto(_ testo: String?) {
        let pulito = testo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = URL(string: pulito), let schema = url.scheme, ["http", "https"].contains(schema.lowercased()) {
            contenuto = .link(url)
        } else if !pulito.isEmpty {
            contenuto = .testo(pulito)
        } else {
            problema = "Non c'è niente da lanciare."
        }
        leggendo = false
    }

    func niente() {
        problema = "Da qui si lanciano foto, link e testi."
        leggendo = false
    }
}

struct VistaCondividiLancio: View {
    @ObservedObject var stato: StatoCondividiLancio
    let fine: () -> Void
    let annulla: () -> Void

    private enum Fase: Equatable {
        case pronto, inVolo, consegna
        case consegnato(String)
    }

    @StateObject private var lanciatore = Lanciatore()
    @State private var fase: Fase = .pronto
    @State private var trascina: CGFloat = 0
    private let tinta = Color.ciano

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [tinta.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button(finito ? "Fine" : "Annulla") { finito ? fine() : annulla() }.tint(tinta)
                }
                TestataScheda(titolo: "Lancio", sottotitolo: sottotitolo, icona: "paperplane", tinta: tinta)
                Text("MIO")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .foregroundStyle(Color.fondo)
                    .background(tinta)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Al tuo Mac: la foto si apre in Anteprima, il link in Safari. Per gli altri c'è già AirDrop nel foglio di condivisione.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.tenue)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack {
                    if stato.leggendo {
                        ProgressView().tint(tinta)
                    } else if let problema = stato.problema {
                        riquadroStato(icona: "exclamationmark.triangle", titolo: "Niente da lanciare", testo: problema, attesa: false)
                    } else {
                        switch fase {
                        case .pronto, .inVolo:
                            scheda
                                .offset(y: fase == .inVolo ? -900 : trascina)
                                .scaleEffect(fase == .inVolo ? 0.5 : 1 + max(-0.06, trascina / 3000))
                                .rotationEffect(.degrees(fase == .inVolo ? -10 : Double(trascina) / 40))
                                .opacity(fase == .inVolo ? 0 : 1)
                                .gesture(trascinamento)
                        case .consegna:
                            riquadroStato(icona: "icloud.and.arrow.up", titolo: "In volo", testo: "Verso il tuo Mac…", attesa: true)
                        case .consegnato(let dove):
                            riquadroStato(icona: "checkmark", titolo: "Sul tuo Mac", testo: dove, attesa: false)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if finito {
                    TastoJarvis(testo: "Ancora", icona: "arrow.uturn.backward", tinta: tinta) {
                        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { fase = .pronto }
                    }
                } else {
                    barraForza
                    TastoJarvis(testo: "Lancia", icona: "paperplane.fill", tinta: tinta) { lancia() }
                        .disabled(!pronto)
                        .opacity(pronto ? 1 : 0.5)
                }
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Suoni.schedaApre()
            lanciatore.alLancio = { lancia() }
            lanciatore.accendi()
            aggiornaArmato()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            Suoni.schedaPronta()
        }
        .onDisappear { lanciatore.spegni() }
        .onChange(of: pronto) { _, _ in aggiornaArmato() }
    }

    // MARK: Pezzi

    private var finito: Bool {
        if case .consegnato = fase { return true }
        return false
    }

    /// Si può lanciare: c'è il contenuto e la scheda è in mano.
    private var pronto: Bool { stato.contenuto != nil && fase == .pronto }

    private var sottotitolo: String {
        switch fase {
        case .pronto: return stato.contenuto == nil ? "acquisizione" : "pronto al lancio"
        case .inVolo, .consegna: return "in volo"
        case .consegnato: return "consegnato"
        }
    }

    private var scheda: some View {
        Pannello(titolo: titoloScheda, tinta: tinta) {
            switch stato.contenuto {
            case .foto(let immagine, _):
                Image(uiImage: immagine)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .link(let url):
                Text(url.absoluteString)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fondo.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            case .testo(let testo):
                Text(testo)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(8)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.fondo.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            case nil:
                EmptyView()
            }
        }
    }

    private var titoloScheda: String {
        switch stato.contenuto {
        case .foto: return "FOTO"
        case .link: return "LINK"
        case .testo: return "TESTO"
        case nil: return ""
        }
    }

    private func riquadroStato(icona: String, titolo: String, testo: String, attesa: Bool) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(tinta.opacity(0.25), lineWidth: 1)
                if attesa {
                    TimelineView(.animation) { ctx in
                        Circle().trim(from: 0, to: 0.3)
                            .stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.radians(ctx.date.timeIntervalSinceReferenceDate * 3.5))
                    }
                }
                Image(systemName: icona).font(.system(size: 28, weight: .medium)).foregroundStyle(tinta)
            }
            .frame(width: 84, height: 84)
            .shadow(color: tinta.opacity(0.5), radius: 12)
            Text(titolo.uppercased())
                .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.white)
            Text(testo)
                .font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.tenue)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }

    private var barraForza: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FORZA").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                Spacer()
                Text(lanciatore.disponibile ? "\(Int(lanciatore.forza * 100))%" : "SENZA SENSORI")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tinta)
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { k in
                    Rectangle()
                        .fill(tinta.opacity(Double(k) < lanciatore.forza * 24 ? 1 : 0.18))
                        .frame(maxWidth: .infinity).frame(height: 8)
                }
            }
            Text("Uno scatto del polso in avanti, o trascina la scheda in su.")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
        }
    }

    // MARK: Il lancio

    private var trascinamento: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { valore in
                guard fase == .pronto else { return }
                let y = valore.translation.height
                trascina = y < 0 ? y : y / 4
            }
            .onEnded { valore in
                if valore.translation.height < -70 && valore.velocity.height < -700 && pronto {
                    lancia()
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { trascina = 0 }
                }
            }
    }

    private func aggiornaArmato() {
        lanciatore.armato = pronto
    }

    private func lancia() {
        guard pronto, let contenuto = stato.contenuto else { return }
        Suoni.chatSvuota()
        ApticaLancio.lancio()
        withAnimation(.timingCurve(0.4, 0, 0.9, 0.6, duration: 0.42)) { fase = .inVolo }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            trascina = 0
            withAnimation(.easeOut(duration: 0.25)) { fase = .consegna }
            let dove = await ConsegnaLancio.mio(contenuto)
            Suoni.fatto()
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { fase = .consegnato(dove) }
        }
    }
}
#endif
