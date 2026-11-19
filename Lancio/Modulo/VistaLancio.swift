#if os(iOS)
import SwiftUI
import UIKit
import PhotosUI

// MARK: - LANCIO: la schermata
// Scegli dove (Mio / Altri / Schermo) e cosa (Foto / Link / Testo), poi lanci: con uno scatto del polso in avanti,
// trascinando la scheda in su veloce, oppure col tasto. La scheda vola via e la consegna parte.
// Si apre col caricamento HUD di JARVIS. Dentro JARVIS riceve `chiudi` e mostra «Chiudi» in alto.

struct VistaLancio: View {
    var chiudi: (() -> Void)? = nil

    private enum Tipo: String, CaseIterable, Identifiable {
        case foto = "Foto", link = "Link", testo = "Testo"
        var id: String { rawValue }
    }

    private enum Fase: Equatable {
        case pronto
        case inVolo
        case consegna                   // Mio: sta scrivendo in iCloud / negli appunti
        case airDrop                    // Altri: AirDrop aperto
        case consegnato(String, String) // titolo, dove trovarlo
    }

    @StateObject private var lanciatore = Lanciatore()
    @ObservedObject private var schermo = SchermoLancio.condiviso
    @Environment(\.scenePhase) private var scena

    @State private var destinazione: DestinazioneLancio = .mio
    @State private var tipo: Tipo = .foto
    @State private var fase: Fase = .pronto

    @State private var sceltaFoto: PhotosPickerItem?
    @State private var foto: UIImage?
    @State private var datiFoto: Data?
    @State private var testoLink = ""
    @State private var testo = ""

    @State private var trascina: CGFloat = 0
    @State private var avviso: String?
    @FocusState private var scrive: Bool

    private let tinta = Color.ciano

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [tinta.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                if let chiudi {
                    HStack {
                        Spacer()
                        Button("Chiudi") { chiudi() }.tint(tinta)
                    }
                }
                TestataScheda(titolo: "Lancio", sottotitolo: sottotitolo, icona: "paperplane", tinta: tinta)
                selettore(DestinazioneLancio.allCases, scelto: destinazione) { nuova in
                    guard fase == .pronto else { return }
                    destinazione = nuova
                } nome: { $0.rawValue }
                Text(notaDestinazione)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.tenue)
                    .fixedSize(horizontal: false, vertical: true)
                selettore(Tipo.allCases, scelto: tipo) { nuovo in
                    guard fase == .pronto else { return }
                    tipo = nuovo
                    scrive = false
                } nome: { $0.rawValue }

                ZStack {
                    switch fase {
                    case .pronto, .inVolo:
                        if schermoMancante {
                            stato(icona: "airplayvideo", titolo: "Schermo scollegato",
                                  testo: "Centro di Controllo › Duplica schermo › il Mac. Poi il lancio atterra sul suo schermo.",
                                  attesa: false)
                        } else {
                            scheda
                                .offset(y: fase == .inVolo ? -900 : trascina)
                                .scaleEffect(fase == .inVolo ? 0.5 : 1 + max(-0.06, trascina / 3000))
                                .rotationEffect(.degrees(fase == .inVolo ? -10 : Double(trascina) / 40))
                                .opacity(fase == .inVolo ? 0 : 1)
                                .gesture(trascinamento)
                        }
                    case .consegna:
                        stato(icona: "icloud.and.arrow.up", titolo: "In volo",
                              testo: tipo == .testo ? "Appunti Universali…" : "iCloud Drive › Lancio…", attesa: true)
                    case .airDrop:
                        stato(icona: "dot.radiowaves.left.and.right", titolo: "AirDrop", testo: "Tocca il Mac a cui mandarlo.", attesa: true)
                    case .consegnato(let titolo, let dove):
                        stato(icona: "checkmark", titolo: titolo, testo: dove, attesa: false)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if case .consegnato = fase {
                    TastoJarvis(testo: "Ancora", icona: "arrow.uturn.backward", tinta: tinta) { ricomincia() }
                } else {
                    barraForza
                    TastoJarvis(testo: "Lancia", icona: "paperplane.fill", tinta: tinta) { lancia() }
                        .disabled(fase != .pronto || schermoMancante)
                        .opacity(fase != .pronto || schermoMancante ? 0.5 : 1)
                }
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .aperturaHUD("Lancio")
        .onAppear {
            lanciatore.alLancio = { lancia() }
            lanciatore.accendi()
            aggiornaArmato()
        }
        .onDisappear { lanciatore.spegni() }
        .onChange(of: scena) { _, nuova in
            if nuova == .active { lanciatore.accendi() } else { lanciatore.spegni() }
        }
        .onChange(of: pronto) { _, _ in aggiornaArmato() }
        .onChange(of: fase) { _, _ in aggiornaArmato() }
        .onChange(of: schermoMancante) { _, _ in aggiornaArmato() }
        .onChange(of: sceltaFoto) { _, nuova in carica(nuova) }
    }

    // MARK: Pezzi della schermata

    private var schermoMancante: Bool { destinazione == .schermo && !schermo.collegato }

    private var notaDestinazione: String {
        switch destinazione {
        case .mio:
            return "Mac con il tuo Apple ID. Solo il gesto: foto in Anteprima e in iCloud Drive, link in Safari, testo negli appunti."
        case .altri:
            return "Mac di un'altra persona: gesto, poi AirDrop e tocchi il Mac."
        case .schermo:
            return schermo.collegato
                ? "Mac collegato in AirPlay: il contenuto atterra sul suo schermo."
                : "Prima collega il Mac: Centro di Controllo › Duplica schermo › il Mac."
        }
    }

    private var sottotitolo: String {
        switch fase {
        case .pronto:
            if schermoMancante { return "in attesa di AirPlay" }
            return pronto ? "pronto al lancio" : "scegli cosa lanciare"
        case .inVolo, .consegna: return "in volo"
        case .airDrop: return "AirDrop"
        case .consegnato: return "consegnato"
        }
    }

    /// Le voci affiancate, come le schede di JARVIS.
    private func selettore<T: Identifiable & Equatable>(_ voci: [T], scelto: T, scegli: @escaping (T) -> Void,
                                                       nome: @escaping (T) -> String) -> some View {
        HStack(spacing: 6) {
            ForEach(voci) { voce in
                let acceso = voce == scelto
                Button { Suoni.tocco(); withAnimation(.snappy(duration: 0.22)) { scegli(voce) } } label: {
                    Text(nome(voce).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .foregroundStyle(acceso ? Color.fondo : tinta)
                        .background(acceso ? tinta : tinta.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(acceso ? 0 : 0.22), lineWidth: 1))
                }
                .buttonStyle(StileStark())
            }
        }
    }

    /// La scheda «in mano»: il contenuto da lanciare.
    @ViewBuilder private var scheda: some View {
        Pannello(titolo: tipo.rawValue.uppercased(), tinta: tinta) {
            switch tipo {
            case .foto:
                PhotosPicker(selection: $sceltaFoto, matching: .images) {
                    if let foto {
                        Image(uiImage: foto)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        vuoto(icona: "photo", testo: "Scegli una foto")
                    }
                }
                .buttonStyle(.plain)

            case .link:
                TextField("https://…", text: $testoLink)
                    .font(.system(size: 15, design: .monospaced))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($scrive)
                    .padding(12)
                    .background(Color.fondo.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                PasteButton(payloadType: URL.self) { indirizzi in
                    guard let primo = indirizzi.first else { return }
                    Task { @MainActor in testoLink = primo.absoluteString }
                }
                .tint(tinta)
                .labelStyle(.titleAndIcon)

            case .testo:
                TextField("Scrivi o incolla…", text: $testo, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(4...8)
                    .focused($scrive)
                    .padding(12)
                    .background(Color.fondo.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                PasteButton(payloadType: String.self) { testi in
                    guard let primo = testi.first else { return }
                    Task { @MainActor in testo = primo }
                }
                .tint(tinta)
                .labelStyle(.titleAndIcon)
            }
            if let avviso {
                Text(avviso).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.orange)
            }
        }
    }

    private func vuoto(icona: String, testo: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icona).font(.system(size: 34, weight: .light))
            Text(testo.uppercased()).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
        }
        .foregroundStyle(tinta)
        .frame(maxWidth: .infinity).frame(height: 200)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 5])))
    }

    private func stato(icona: String, titolo: String, testo: String, attesa: Bool) -> some View {
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

    /// La barra «Forza» a segmenti, come il caricamento di JARVIS.
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
            Text(pronto ? "Uno scatto del polso in avanti, o trascina la scheda in su." : "Prima scegli cosa lanciare.")
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
                let veloce = valore.velocity.height < -700
                if valore.translation.height < -70 && veloce && pronto {
                    lancia()
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0.35)) { trascina = 0 }
                }
            }
    }

    /// Quello che si lancia, se c'è.
    private var contenuto: ContenutoLancio? {
        switch tipo {
        case .foto:
            guard let foto, let datiFoto else { return nil }
            return .foto(foto, datiFoto)
        case .link:
            let pulito = testoLink.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pulito.isEmpty else { return nil }
            let completo = pulito.contains("://") ? pulito : "https://" + pulito
            guard let url = URL(string: completo), url.host() != nil else { return nil }
            return .link(url)
        case .testo:
            let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
            return pulito.isEmpty ? nil : .testo(pulito)
        }
    }

    private var pronto: Bool { contenuto != nil }

    private func aggiornaArmato() {
        lanciatore.armato = pronto && fase == .pronto && !schermoMancante
    }

    private func lancia() {
        guard fase == .pronto, !schermoMancante else { return }
        guard let contenuto else {
            Suoni.errore()
            withAnimation { avviso = tipo == .link ? "Serve un indirizzo valido." : "Non c'è niente da lanciare." }
            withAnimation(.spring(duration: 0.3, bounce: 0.35)) { trascina = 0 }
            return
        }
        avviso = nil
        scrive = false
        Suoni.chatSvuota()
        ApticaLancio.lancio()
        withAnimation(.timingCurve(0.4, 0, 0.9, 0.6, duration: 0.42)) { fase = .inVolo }

        Task {
            try? await Task.sleep(for: .milliseconds(420))
            trascina = 0
            switch destinazione {
            case .mio:
                withAnimation(.easeOut(duration: 0.25)) { fase = .consegna }
                let dove = await ConsegnaLancio.mio(contenuto)
                Suoni.fatto()
                withAnimation(.spring(duration: 0.45, bounce: 0.3)) { fase = .consegnato("Sul tuo Mac", dove) }
            case .altri:
                withAnimation(.easeOut(duration: 0.25)) { fase = .airDrop }
                ConsegnaLancio.altri(contenuto) { inviato in
                    if inviato {
                        Suoni.fatto()
                        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                            fase = .consegnato("Inviato", "Con AirDrop: sul Mac è nei Download.")
                        }
                    } else {
                        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { fase = .pronto }
                    }
                }
            case .schermo:
                schermo.mostra(contenuto)
                Suoni.fatto()
                withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                    fase = .consegnato("Sullo schermo", "Si vede sul Mac. Il file resta sull'iPhone.")
                }
            }
        }
    }

    private func ricomincia() {
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { fase = .pronto }
    }

    private func carica(_ scelta: PhotosPickerItem?) {
        guard let scelta else { return }
        Task {
            guard let dati = try? await scelta.loadTransferable(type: Data.self),
                  let immagine = UIImage(data: dati) else {
                avviso = "Questa foto non si riesce ad aprire."
                return
            }
            foto = immagine
            datiFoto = immagine.jpegData(compressionQuality: 0.9) ?? dati
            avviso = nil
        }
    }
}

#Preview {
    VistaLancio()
}
#endif
