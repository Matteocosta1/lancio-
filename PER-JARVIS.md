# Lancio dentro JARVIS — istruzioni per Claude (sessione di JARVIS)

Alessandro dirà: «integra Lancio dal repo lancio- seguendo PER-JARVIS.md». Questi sono i passi.
Prima di toccare JARVIS: spiegargli il piano e aspettare il suo sì (regole di JARVIS).

## 1. Cosa si copia
- Copiare in JARVIS **solo la cartella `Lancio/Modulo/`** (in `Untitled Project/`, anche in una sottocartella `Lancio`).
  I file sono già racchiusi in `#if os(iOS)`.
- **Non** copiare `Lancio/SoloApp/`: contiene copie di pezzi che in JARVIS esistono già
  (`Color.ciano/fondo/tenue`, `StileStark`, `TestataScheda`, `Pannello`, `TastoJarvis`, `CaricamentoHUD`,
  `aperturaHUD`, `Suoni`) e il `@main` dell'app da sola.
- Il Modulo usa di JARVIS: `Suoni.tocco()`, `Suoni.chatSvuota()` (suono del lancio), `Suoni.fatto()`, `Suoni.errore()`,
  `.aperturaHUD("Lancio")`, `TestataScheda`, `Pannello`, `TastoJarvis`, `StileStark`, `Color.ciano/fondo/tenue`.
  Nomi del Modulo, già controllati liberi in JARVIS: `VistaLancio`, `Lanciatore`, `ApticaLancio`, `ContenutoLancio`,
  `DestinazioneLancio`, `ConsegnaLancio`, `SchermoLancio`, `SchermoLancioDelegato`, `VistaSchermoLancio`.

## 1b. Il lancio dentro JARVIS (V4)
- Alla ContentView di JARVIS: `.riceviLancio()` (una volta sola): accende la rete, mostra «Accetta», la schermata d'arrivo.
- Alla foto aperta nella sezione Foto: `.lanciabile(.foto(immagine, jpeg))` (il JPEG si prepara con `ImmagineLancio.jpegRidotto`).
- Al Browser di JARVIS: `.lanciabile(urlAttuale.map { .link($0) })`.
- Info.plist di JARVIS: `NSBonjourServices` = `_lancio-jv._tcp`, `_lancio-jv._udp` e `NSLocalNetworkUsageDescription`
  (vedi `Config/Info.plist`). Stesso nome di servizio dell'app da sola: si trovano tra loro.
- JARVIS gira già sul Mac: con `.riceviLancio()` il Mac riceve senza installare altro.

## 2. Dove si apre (da confermare con Alessandro)
- Icona nella corona, gruppo **STRUMENTI**, dopo LiDAR:
  `("STRUMENTI", "paperplane", "Lancio", { tastiera = false; mostraLancio = true })`
  con `.fullScreenCover(isPresented: $mostraLancio) { VistaLancio(chiudi: { mostraLancio = false }) }`
  e `mostraLancio = false` in `chiudiTutto()`.
- Comando vocale: `Reparto.lancio`, annuncio «Lancio pronto, Sir.».

## 3. iCloud (per «Mio»: foto e link sul Mac)
- Aggiungere alle entitlements di JARVIS il contenitore **`iCloud.it.discosizer.lancio`**
  (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.ubiquity-container-identifiers`,
  `com.apple.developer.icloud-services` = `CloudDocuments`). È lo stesso dell'app da sola: le automazioni
  di Comandi sul Mac continuano a funzionare senza cambiare niente.
- Nell'Info.plist di JARVIS, `NSUbiquitousContainers` › `iCloud.it.discosizer.lancio`:
  `NSUbiquitousContainerIsDocumentScopePublic` = YES, `NSUbiquitousContainerName` = `Lancio`,
  `NSUbiquitousContainerSupportedFolderLevels` = `Any` (vedi `Config/Info.plist` di questo repo).

## 4. Schermo (AirPlay)
- Nel delegato dell'app di JARVIS (`Notifiche`, quello di `@UIApplicationDelegateAdaptor`) aggiungere:
  ```swift
  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
      SchermoLancio.configurazione(per: connectingSceneSession) ?? connectingSceneSession.configuration
  }
  ```
- **Decisione da chiedere ad Alessandro:** con questo, quando l'iPhone duplica lo schermo su un Mac o una TV,
  JARVIS mostra lì la schermata di Lancio invece di duplicare tutto lo schermo. Va bene sempre, o solo con Lancio aperto?

## 5. Estensione Condividi «Lancia»
- Nuovo target «Share Extension» in JARVIS (nome visibile: «Lancia»), con `LancioCondividi/ControllerCondividi.swift`
  e la `NSExtension` di `Config/LancioCondividi-Info.plist`; entitlements con lo stesso contenitore iCloud del punto 3.
- Il target deve compilare anche: `Modulo/Consegna.swift`, `Gesto.swift`, `ImmagineLancio.swift`, `VistaCondividiLancio.swift`
  e, da JARVIS, i pezzi grafici e `Suoni` (se i file di JARVIS non si possono condividere col target, servono le copie di `SoloApp`).
- NON vanno nel target: `AirDropLancio.swift`, `Schermo.swift`, `VistaLancio.swift` (usano API vietate nelle estensioni).

## 6. Dopo
- Advisor/controlli di JARVIS, push con `[compila]`, numero di versione di JARVIS.
