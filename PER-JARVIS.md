# Il lancio dentro JARVIS — istruzioni per Claude (sessione di JARVIS)

Alessandro dirà: «integra il lancio dal repo lancio- seguendo PER-JARVIS.md».
Prima di toccare JARVIS: spiegargli il piano in parole semplici e aspettare il suo sì (regole di JARVIS).

## L'idea (come la vuole Alessandro)
Non esiste un'app «Lancio»: è una funzione di JARVIS. In JARVIS apri una foto, un video, un link o qualsiasi cosa,
fai lo scatto del polso in avanti e parte. Niente da aprire, niente tasti. Chi riceve non ha niente installato:
- c'è uno schermo collegato in AirPlay (TV, Apple TV, Mac) → il contenuto ci atterra sopra, senza tocchi;
- altrimenti → si apre AirDrop con le persone vicine, se ne tocca una e le arriva la notifica
  (quel tocco Apple non lo lascia togliere a nessuna app).

## 1. Cosa si copia in JARVIS (in `Untitled Project/`, anche in una sottocartella `Lancio`)
Da `Lancio/Modulo/`:
- `Gesto.swift` — il riconoscimento dello scatto (`Lanciatore`) e la vibrazione (`ApticaLancio`)
- `Lanciabile.swift` — `.lanciabile(…)`: gesto, volo della schermata, AirPlay o AirDrop
- `Consegna.swift` — `ContenutoLancio` (foto, video, link, testo) e `ConsegnaLancio`
- `AirDropLancio.swift` — il foglio con AirDrop in cima
- `Schermo.swift` — lo schermo AirPlay: la schermata HUD sul TV/Mac e l'atterraggio (anche dei video)
- `ImmagineLancio.swift` — la foto ridotta a JPEG 3072 px, pronta da lanciare

NON si copiano: `VistaLancio.swift`, `FotoLancio.swift`, `WebLancio.swift` (sono solo il banco di prova),
`VistaCondividiLancio.swift` e la cartella `LancioCondividi/` (estensione dell'app di prova), la cartella `SoloApp/`
(copie di pezzi che in JARVIS esistono già: colori, `TestataScheda`, `Pannello`, `TastoJarvis`, `StileStark`,
`CaricamentoHUD`, `aperturaHUD`, `Suoni`).

Il Modulo usa di JARVIS: `Suoni.chatSvuota()` (suono del lancio), `Suoni.fatto()`, `Color.ciano/fondo/tenue`.
Nomi del Modulo, controllati liberi in JARVIS: `Lanciatore`, `ApticaLancio`, `Lanciabile`, `ContenutoLancio`,
`DestinazioneLancio`, `ConsegnaLancio`, `SchermoLancio`, `SchermoLancioDelegato`, `VistaSchermoLancio`, `ImmagineLancio`.

## 2. Dove si aggiunge il gesto (da confermare con Alessandro, schermata per schermata)
- `Galleria.swift` › `VistaImmagini` (le immagini a schermo intero): alla pagina attuale
  `.lanciabile(.foto(immagine, jpeg))`, con il JPEG preparato da `ImmagineLancio.jpegRidotto(dati)`.
- `SchedeSensi.swift` › `VistaFotoScheda` (sezione Foto): sulla foto aperta, come sopra.
- `BrowserPrivato.swift` › `BrowserPrivato`: `.lanciabile(paginaAttuale.map { .link($0) })` con l'URL della `WKWebView`.
- `Galleria.swift` › `BrowserInterno` (Safari interno): `.lanciabile(.link(url))`.
- Video: dove JARVIS mostra un video, `.lanciabile(.video(urlDelFile))`.
- Testo: dove ha senso (es. una risposta di JARVIS aperta), `.lanciabile(.testo(testo))`.

## 3. Lo schermo AirPlay
Nel delegato dell'app di JARVIS (`Notifiche`, quello di `@UIApplicationDelegateAdaptor`) aggiungere:
```swift
func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                 options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    SchermoLancio.configurazione(per: connectingSceneSession) ?? connectingSceneSession.configuration
}
```
Con questo, quando l'iPhone è collegato a una TV o a un Mac (Centro di Controllo › Duplica schermo), JARVIS mostra lì
la sua schermata HUD «in attesa di lancio» e ci fa atterrare quello che lanci. **Da dire ad Alessandro:** mentre è
collegato, lo schermo mostra JARVIS invece della copia dell'iPhone.

## 4. Permessi
Nessun permesso nuovo: CoreMotion (il gesto) non chiede niente, AirDrop e AirPlay sono di sistema.

## 5. Dopo
Controlli di JARVIS (import, main actor, zero warning), push con `[compila]`, numero di versione di JARVIS.
