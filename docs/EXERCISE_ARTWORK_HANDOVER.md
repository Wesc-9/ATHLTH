# ATHLTH — overlevering for øvelsesillustrasjoner (28.11.2026)

## Mål og arbeidsregler
- Erstatt alle eksisterende repDB-illustrasjoner med originale ATHLTH-bilder, uten å endre øvelses-ID-er, historikk, favoritter, treningsplaner eller data. Behold repDB-dataattribusjon. Arbeid direkte på release/v3.0.7, ikke PR. Kontroller grenens aktuelle HEAD før endringer.
- Maks fire bilder per generering (to øvelser, to kvadratiske bilder hver). Veksle mann/kvinne som første figur; start og slutt må alltid være korrekt. Statiske øvelser kan vises fra to vinkler.
- Bruk den sist godkjente firebilders referansen (sideplanke og dead bug, 223776DB-0336-4422-8274-618691FE651B.jpeg) fra samtalen, samt original ATHLTH-logo. Samme figurer, klær og krembakgrunn. Lite hvitt ATHLTH-symbol på brystet, uten tekst, naturlig perspektiv; ingen logo på tights/shorts, ingen ekstra dekor. Ikke improviser merke eller skaler tekst opp. Hvite sko, sorte klær. Kontroller visuelt mot referansen før import.
- 832 × 832 px, WebP, 20–30 kB ønsket, 40 kB foretrukket øvre mål per bilde. Generer helst i full oppløsning; ikke forveksle oppskalering med ekte detalj. Offline, eksisterende cache og nedskalering. Korrekt anatomi, utstyr og utførelse er viktigere enn tempo.
- Behold eksisterende muskelkart. Ikke legg til de ni andre foreslåtte nye kjerneøvelsene uten ny bestilling.

## Bekreftet i GitHub før denne dokumentasjonen
Gren: release/v3.0.7. HEAD cdb2f574a694bc763074ddcb1c4a815176143ee1.
- Planke med vekt / Weighted Plank: egen native ID athlth-native-weighted-plank, NO/EN navn og instruksjoner, to bilder (55 044 bytes), commit 28e4483745fb4ec1dcc6f904a459e857e5125297, utstyrslokalisering f23a827e1c2945f1beda5e4e2b235478d749546a.
- Erstatningsinfrastruktur: 14abcdda97a91e54b3af3afa2591cb5d5a982b07. For repDB: ATHLTH/Resources/ATHLTHExerciseArtwork.bundle/<eksakt-id>-start.webp og <eksakt-id>-peak.webp. Fullstendig par erstatter gamle bilder; byggeskript utelater de gamle bildene hvis ingen udekkede øvelser bruker dem. Eksisterende bilder fungerer som fallback under overgangen.
- Vanlig planke (plank, kvinne først) og magecrunch (crunches, mann først): fire WebP-filer på gren, commit cdb2f574a694bc763074ddcb1c4a815176143ee1, samlet 84 420 bytes. Seks bilder totalt i repo, tre øvelser. Xcode-test og TestFlight ikke verifisert.

## Neste steg
1. Pakke 02 med side-plank og dead-bug er produsert og klargjort lokalt (ATHLTH-core-batch-02.zip), men ikke committet. Kontroller hvert bilde mot den sist godkjente referansen og teknisk utførelse før import. Ikke importer senere forkastede kollasjer.
2. Deretter bird-dog og russian-twist (kontroller eksakt variant/utstyr; ikke forveksle med weighted Russian twist), så reverse-crunches, hanging-leg-raise, bicycle-crunch, ab-wheel-rollout. Kontroller eksakte repDB-ID-er mot aktuell katalog.
3. Fortsett mage/kjerne, deretter bryst, rygg, skuldre, armer, bein/sete og øvrige øvelser. Før status per faktisk committet par, ikke antall utkast.
4. Kjør relevante regresjons- og Xcode-tester. Ikke påstå at en test er kjørt eller at et bilde er på release uten verifisering.

Katalogmåling: 1231 WebP-filer i repDBs offentlige flat-katalog, ca. 20,28 MB. Dette er antall bilder, ikke antall øvelser. Nye bilder er ca. 27,5 kB i gjennomsnitt for den første vektplanken. Ingen automatisk bakgrunnsproduksjon er startet.
