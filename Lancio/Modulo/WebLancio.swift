#if os(iOS)
import SwiftUI
import UIKit
import Combine
import WebKit

// MARK: - WEB: la pagina che guardi, da lanciare
// Un browser essenziale: scrivi un indirizzo o una ricerca, navighi, e con lo scatto del polso parte
// il link della pagina che hai davanti. Dall'altra parte si apre in Safari.
// In JARVIS il Browser c'è già: lì basta aggiungere `.lanciabile(paginaAttuale.map { .link($0) })`.

final class PaginaWebLancio: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var url: URL?
    @Published private(set) var titolo = ""
    @Published private(set) var caricando = false
    @Published private(set) var indietro = false
    @Published private(set) var avanti = false

    let vista: WKWebView

    override init() {
        let configurazione = WKWebViewConfiguration()
        configurazione.allowsInlineMediaPlayback = true
        vista = WKWebView(frame: .zero, configuration: configurazione)
        super.init()
        vista.navigationDelegate = self
        vista.allowsBackForwardNavigationGestures = true
        vista.isOpaque = false
        vista.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)
    }

    /// Un indirizzo («apple.com», «https://…») o una ricerca («dischi rari»).
    func vai(_ testo: String) {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pulito.isEmpty else { return }
        let destinazione: URL?
        if pulito.contains("://") {
            destinazione = URL(string: pulito)
        } else if pulito.contains("."), !pulito.contains(" ") {
            destinazione = URL(string: "https://" + pulito)
        } else {
            var ricerca = URLComponents(string: "https://www.google.com/search")
            ricerca?.queryItems = [URLQueryItem(name: "q", value: pulito)]
            destinazione = ricerca?.url
        }
        guard let destinazione else { return }
        vista.load(URLRequest(url: destinazione))
    }

    func tornaIndietro() { vista.goBack() }
    func vaiAvanti() { vista.goForward() }

    private func aggiorna() {
        url = vista.url
        titolo = vista.title ?? ""
        caricando = vista.isLoading
        indietro = vista.canGoBack
        avanti = vista.canGoForward
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { aggiorna() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { aggiorna() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { aggiorna() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { aggiorna() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        aggiorna()
    }
}

struct VistaWebLancio: View {
    @ObservedObject var pagina: PaginaWebLancio
    @State private var indirizzo = ""
    @FocusState private var scrive: Bool
    private let tinta = Color.ciano

    var body: some View {
        VStack(spacing: 0) {
            barraIndirizzo
            ZStack {
                if pagina.url == nil {
                    vuota
                } else {
                    WebViewLancio(vista: pagina.vista)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .lanciabile(pagina.url.map { ContenutoLancio.link($0) })
        }
        .onChange(of: pagina.url) { _, nuovo in
            if !scrive { indirizzo = nuovo?.absoluteString ?? "" }
        }
    }

    private var barraIndirizzo: some View {
        HStack(spacing: 8) {
            Button { Suoni.tocco(); pagina.tornaIndietro() } label: { Image(systemName: "chevron.left") }
                .disabled(!pagina.indietro)
            Button { Suoni.tocco(); pagina.vaiAvanti() } label: { Image(systemName: "chevron.right") }
                .disabled(!pagina.avanti)
            HStack(spacing: 6) {
                Image(systemName: pagina.caricando ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.tenue)
                TextField("Indirizzo o ricerca", text: $indirizzo)
                    .font(.system(size: 14, design: .monospaced))
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($scrive)
                    .onSubmit { pagina.vai(indirizzo) }
            }
            .padding(.horizontal, 10).frame(height: 38)
            .background(tinta.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.22), lineWidth: 1))
        }
        .font(.system(size: 15, weight: .semibold))
        .tint(tinta)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var vuota: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe").font(.system(size: 30, weight: .light)).foregroundStyle(tinta)
            Text("WEB")
                .font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.white)
            Text("Apri una pagina, poi lanciala: dall'altra parte si apre in Safari.")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }
}

struct WebViewLancio: UIViewRepresentable {
    let vista: WKWebView

    func makeUIView(context: Context) -> WKWebView { vista }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
