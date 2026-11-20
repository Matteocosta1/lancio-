# Lancio — regole per Claude

Il «lancio» è una funzione di JARVIS, non un'app: in JARVIS apri una foto, un video, un link o un testo, fai lo
scatto del polso e parte. Schermo AirPlay collegato → atterra lì senza tocchi; altrimenti → AirDrop (si tocca la
persona). Chi riceve non installa niente. Il progetto `Lancio.xcodeproj` è solo il banco di prova del gesto. Il progetto è di **Alessandro** (crea e decide tutto);
Matteo è il suo socio. Lancio nasce da solo per provarlo, poi **entra in JARVIS** (repo `Matteocosta1/jarvis`):
stessa grafica, stessi suoni, stesse regole.

- **Ramo di Xcode:** `main`.
- Ogni modifica si numera **V1, V2, V3…** e va scritta in `VERSIONI.md`, così si può togliere una sola versione.
- `Lancio/Modulo/` è il blocco che entra in JARVIS (istruzioni in `PER-JARVIS.md`): usa solo nomi già liberi in JARVIS
  e chiama i pezzi di JARVIS (`Suoni`, `aperturaHUD`, `TestataScheda`, `Pannello`, `TastoJarvis`, colori).
- `Lancio/SoloApp/` contiene le copie di quei pezzi per l'app da sola: in JARVIS non si copia.
- Il codice di JARVIS non si tocca da qui: l'integrazione si fa nella sessione di JARVIS.

## Come si lavora con Alessandro
- Prima di modificare il codice: spiegare in parole semplici cosa si vuole fare e aspettare il suo sì.
- Design, grafica, suoni e struttura li decide lui. Mai togliere voci o funzioni senza chiedere.
- Proporre sempre la soluzione migliore, non la scorciatoia. Se Apple non permette una cosa, dirlo subito.
- Version e Build li gestisce Claude, ma il numero di build non si alza da soli: prima chiedere.
- Le build vanno su TestFlight col suo metodo (Pull + Archive + TestFlight).

## Prima di dire "pronta" (qui Xcode non c'è)
1. Ricontrollare a mano ogni file: `import Combine` dove ci sono `@Published`/`ObservableObject`, nomi ambigui,
   codice del thread principale chiamato da closure che non girano sul main actor, tipi espliciti nelle tuple.
   Il progetto usa le stesse impostazioni di JARVIS: Swift 5, isolamento predefinito `MainActor`, iOS 27.
2. Zero errori e zero warning.
3. Push con **`[compila]`** nel messaggio del commit, poi leggere il workflow **Compila**: consegnare solo se è verde.
4. Dire chiaro cosa è fatto, cosa no e cosa va provato sul telefono.

## Nell'app
- Animazioni a 120 Hz, funzionali, niente animazioni inutili. Titoli di una parola. Numeri scritti a schermo.
