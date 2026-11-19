# Lancio — versioni

Ogni modifica riceve un numero (V1, V2…). "Togli la VN" = `git revert` dei commit di quella versione (mai riscrivere la storia).
Dopo ogni cambio: in Xcode **Integrate › Pull**.

| Versione | Data | Chi | Cosa |
|---|---|---|---|
| V1 | 19 nov 2026 | Alessandro | Prima versione. Schermata Lancio con la grafica di JARVIS (fondo scuro, ciano, testata HUD). Si sceglie dove (Mio / Altri) e cosa (Foto / Link / Testo). Lancio con uno scatto del polso (giroscopio + accelerometro, barra Forza), trascinando la scheda in su o col tasto. Mio: Appunti Universali (⌘V sul Mac), link anche via Handoff nel Dock, foto anche in iCloud Drive › Lancio. Altri: si apre AirDrop. Build 1. |
| V2 | 19 nov 2026 | Alessandro | Tre destinazioni: Mio, Altri, Schermo. Schermo: col Mac collegato in AirPlay, Lancio disegna sul Mac la sua schermata HUD e il contenuto ci atterra. Mio: foto in iCloud Drive › Lancio › Foto e link (segnalibro) in Lancio › Link, così l'automazione di Comandi del Mac li apre in Anteprima e Safari; testo negli appunti. Suoni di JARVIS (tick, scheda, schedapronta, pronto; il lancio usa «chatsvuota»). Apertura col caricamento HUD di JARVIS. Codice diviso in Modulo (da copiare in JARVIS) e SoloApp; istruzioni in PER-JARVIS.md. Build 1. |
