#if os(iOS)
import SwiftUI
import UIKit

// MARK: - VICINI: chi c'è intorno, il tuo nome, i fidati

struct VistaViciniLancio: View {
    @ObservedObject private var rete = ReteLancio.condivisa
    @State private var nome = ""
    @FocusState private var scrive: Bool
    private let tinta = Color.ciano

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Pannello(titolo: "QUESTO DISPOSITIVO", tinta: tinta) {
                    TextField("Nome", text: $nome)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .submitLabel(.done)
                        .focused($scrive)
                        .onSubmit { rete.cambiaNome(nome) }
                        .padding(12)
                        .background(Color.fondo.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(rete.attiva ? "Visibile agli altri con questo nome." : "Non visibile: l'app è in secondo piano.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.tenue)
                }

                Pannello(titolo: "INTORNO A TE · \(rete.vicini.count)", tinta: tinta) {
                    if rete.vicini.isEmpty {
                        Text("Nessuno. Sugli altri dispositivi apri Lancio e lascialo aperto: compaiono qui da soli.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.tenue)
                    } else {
                        ForEach(rete.vicini) { vicino in
                            riga(icona: vicino.icona, nome: vicino.nome, nota: rete.fidati[vicino.id] != nil ? "FIDATO" : nil)
                        }
                    }
                }

                Pannello(titolo: "FIDATI · \(rete.fidati.count)", tinta: tinta) {
                    if rete.fidati.isEmpty {
                        Text("Quando accetti un lancio con «Sempre da questo dispositivo», quel dispositivo compare qui e da lì in poi arriva senza chiedere.")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.tenue)
                    } else {
                        ForEach(rete.fidati.sorted { $0.value < $1.value }, id: \.key) { voce in
                            HStack {
                                riga(icona: "checkmark.shield", nome: voce.value, nota: nil)
                                Button { Suoni.tocco(); rete.dimentica(voce.key) } label: {
                                    Image(systemName: "xmark.circle").font(.system(size: 16))
                                }
                                .tint(tinta)
                                .accessibilityLabel("Togli \(voce.value) dai fidati")
                            }
                        }
                    }
                }

                Text("Per ricevere sul Mac: apri Lancio sul Mac e lascialo aperto. Si trovano anche senza la stessa Wi-Fi, come con AirDrop.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.tenue)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { nome = rete.nome }
        .onChange(of: scrive) { _, attivo in
            if !attivo { rete.cambiaNome(nome) }
        }
    }

    private func riga(icona: String, nome: String, nota: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icona).font(.system(size: 17)).foregroundStyle(tinta).frame(width: 26)
            Text(nome).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
            Spacer()
            if let nota {
                Text(nota).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(tinta)
            }
        }
        .frame(height: 36)
    }
}
#endif
