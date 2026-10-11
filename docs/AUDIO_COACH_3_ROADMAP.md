# ATHLTH Audio Coach 3.0 — utviklingsplan og akseptansesjekkliste

**Baseline:** `release/v1.7.3` (11.10.2026). Bevar fungerende løpe-, styrke- og Watch-opptak, HealthKit, Spotify og eksisterende meldinger. Arbeid i små, reversible commits **direkte på aktiv release-gren uten PR**. **Ikke send til TestFlight uten uttrykkelig beskjed.**

## Mål

Audio Coach skal være integrert i alle støttede økter fra planlegging til oppsummering, fungere uten nett, snakke presist og sjelden nok, og gi korrekt ansvar for tale/haptikk på iPhone og Apple Watch. Ikke krev AI eller ekstern deling av helseopplysninger for grunnfunksjonene.

**Definisjon av ferdig:** Hvert steg testes på tilgjengelige automatiserte tester, iOS/watchOS-bygger og fysisk iPhone+Watch når lydruter er involvert. Kode implementert uten bekreftet bygg/fysisk test skal markeres eksplisitt som *ikke verifisert*.

## Status / stegvis rekkefølge

### 1A. Foreløpig sikkerhetsnett for Watch/iPhone-lyd — IMPLEMENTERT, BYGG/ENHETSTEST AVVENTER

- [x] Eksplisitt, testbar prioriteringspolicy (`ATHLTHAudioCoachVoiceRouting`) i delt modell.
- [x] Behold vanlige løpemeldinger og strukturert løpesteg på speilet iPhone når telefon foretrekkes og er tilgjengelig.
- [x] La Watch beholde Ghost, puls-/tempomål og kritiske rutevarsler som den speilede iPhone-coachen ikke reproduserer.
- [x] La Watch beholde alle styrkeinstruksjoner ved speiling; undertrykk iPhone-speilet generisk styrketale for å unngå dobbel tale.
- [x] Enhetstester for prioriteringsmatrise, frakoblet iPhone, styrke, vandring, eldre konfigurering og prioritetsgate.
- [ ] iOS + Watch build grønne på relevant commit.
- [ ] Test fysisk lyd i AirPods/iPhone høyttaler/Watch-høyttaler, og rask til/frakobling.
- [ ] Verifiser at kritiske klokkevarsler høres når hodetelefoner brukes på iPhone.

**Begrensning:** At telefonen er `WCSession.isReachable` er *ikke* bevis for at den faktisk kan levere tale. Denne første endringen sikrer unike Watch-meldinger, men fullfører ikke bekreftet lydansvar, og talekanaler kan i sjeldne tilfeller overlappe. 1B må derfor komme før en full «garantert» overlevering kan hevdes.

### 1B. Bekreftet lydansvar og hendelseslevering — PROTOKOLL IMPLEMENTERT, IKKE FULLT VERIFISERT

- [x] Eksplisitt iPhone→Watch lease-offer og Watch→iPhone ACK for ordinære løpevarsler; telefonen snakker først etter bekreftelse (for nyere Watch).
- [x] Hver lease er bundet til øktens starttid, unik generasjon og request-ID; 6 s Watch-utløp / 4,5 s iPhone-utløp, fornyes kun med fersk speiling.
- [x] Ved manglende ACK / utløpt bekreftelse tar Watch over tale; Ghost, mål-/rutevarsler og styrke forblir Watch-eid.
- [x] Eldre Watch-snapshots støttes gjennom bakoverkompatibel capabilities-markør og eksisterende lydvei.
- [x] Enhetstester lagt til for utløp, gammel/feil økt, feil rekkefølge, serialisering og blandede versjoner.
- [ ] Verifiser full iOS/Watch-bygg og tester på relevant commit (CI-status separat).
- [ ] Verifiser fysisk lydlevering under normal start, til-/frakobling, pause, gjenopptak og avslutning.
- [ ] Full dedup per **hendelses-ID** og frister/utløp på meldinger; håndteres sammen med typed Coach Event Engine i steg 2.
- [ ] Sikker lydruteoverlevering ved Spotify/AirPods/Watch-høyttaler, telefon uten lydrute, iPhone i bakgrunn og app-restart.
- [ ] Bevis gjennom fysisk test at **ingen** dobbelte eller manglende rutinemeldinger forekommer ved handoff.

**Viktig presisering:** ACK bekrefter at Watch har mottatt leieforespørselen og at økten matcher; den bekrefter **ikke** at en fysisk lydutgang fungerer eller at brukeren hørte meldingen. Må ikke omtales som fullstendig «garantert lydlevering» før lydrute- og hendelsesleveringstester er gjennomført.

### 2. Felles Coach Event Engine — STEG 2A IMPLEMENTERT; 2B GJENSTÅR

**2A: Lokal hendelsesidentitet, deduplisering og utløp – KODE IMPLEMENTERT, BYGG/ENHETSTEST AVVENTER**

- [x] Delt, lettvekts `ATHLTHCoachEventKind` med typer for øktstart/pause/avslutning, plansteg, milepæl, mål/rute/Ghost, styrkesett/hvile og manuell status.
- [x] `ATHLTHCoachEventLedger`: stabil identitet per type+nøkkel, tidsfrist for levering, lokal duplikatkontroll, reset ved ny økt og maksimum 256 markører.
- [x] iPhone-opptak: rutinemilepæler og strukturerte trinn koblet til ledgeren.
- [x] Apple Watch: rutinemilepæler, plantrinn og øktstart koblet til ledgeren. Utløpte milepæler droppes også etter asynkron aktivering av lydrute.
- [x] Speilet iPhone: rutinemilepæler og plantrinn koblet til ledgeren med tidsstempel fra speilet snapshot.
- [x] Enhetstester: duplicate, eventtyper, manglende/ugyldig nøkkel, gammelt tidsstempel, minnegrense og reset.
- [ ] Bekreftet godkjent iOS+Watch-bygg og automatisk testkjøring på den samlede grenen.

**2B: Leveringssikkerhet og flere kategorier — DELLEVERANSE IMPLEMENTERT, VERIFISERING GJENSTÅR**

- [x] Felles, tidsbegrenset `ATHLTHCoachCueQueue`: maks 6 ventende meldinger, viktigste først, eldste ved lik prioritet, erstatt tidligere status av samme type.
- [x] Rutinemeldinger legges ikke i kø; viktige steg-, Ghost-, mål- og rutevarsler kan vente kort når stemmen er opptatt.
- [x] Koblet til Audio Coach på iPhone, speilet iPhone og Apple Watch; ventende melding leses først når pågående tale faktisk er avsluttet.
- [x] Styrkens talemotor bruker samme prinsipp i stedet for alltid å avbryte tale; hvilemeldinger kategoriseres særskilt med kortere utløp.
- [x] Enhetstester for prioriteringsrekkefølge, FIFO, coalescing, dubletter, utløp, begrenset kø og reset.
- [ ] Fullført grønn iOS + watchOS-bygg og kjøring av testene mot siste samlede commit.
- [x] **Delvis hendelseskvittering fra iPhone til Watch:** kortvarig, øktbundet `ATHLTHCoachDeliveryReceipt` for milepæler og løpesteg (hendelsestype/nøkkel, øktens starttid og sendetid, ingen tale-/helsetekst). Watch sjekker økt, alder og tillatt type før lokal dublettmarkering.
- [x] **Toveis best-effort-kvittering for tale-forsøk:** Watch→iPhone er koblet til den samme HealthKit-speilingen som iPhone→Watch. Bare ferske kvitteringer for riktig økt og tillatte hendelses-ID-er registreres. Watch sjekker lydansvar og ledger **etter** lydaktivering, før tale starter.
- [ ] ACK på **faktisk hørbar avspilling** og full exactly-once-attempt/levering ved krasj, utfall og alle ruteoverganger; kan ikke garanteres av dagens speilings-API.
- [x] `ATHLTHCoachSensorFreshness` med plausibilitets- og tidsgrenser for puls (12 s), GPS-tempo (8 s) og speilet snapshot (5 s).
- [x] Watch-målsonevarsler krever ferske puls- og tempomålinger. Stale signaler kan heller ikke utløse falsk «tilbake i målområdet».
- [x] Speilet iPhone leser ikke opp gamle puls-/tempotall; eldre Watch-versjoner uten måletidsstempler behandles konservativt.
- [x] iPhone-løping utelater gammel GPS-basert tidsprognose i Audio Coach.
- [x] Testtilfeller for ugyldige/utdaterte sensorer, gamle kvitteringer, feil økt, øktbytte, begrenset dublettlager og bakoverkompatible snapshot-felt.
- [x] Felles `ATHLTHCoachAlertChannels` brukes for rute-/målalerts på både iPhone og Watch: tale og haptikk evalueres uavhengig, slik at stengt lydkanal ikke fjerner tillatt sikkerhetsvibrasjon.
- [ ] Lokaliseringsgjennomgang og kanalregler for **øvrige** styrke-, Ghost- og rutinemeldinger.
- [ ] Event-telemetri uten identifiserende eller følsomme treningsopplysninger.
- [ ] Fysisk test av AirPods/Spotify, bakgrunn, pause/fortsett, live Ghost og iPhone-til-/frakobling.

**Merknad:** Implementert prioritetskø og toveis kvittering for et **tale-forsøk** er fortsatt *best-effort*. Kvitteringen er ikke bevis for at lyd faktisk ble hørt. Dette gjelder foreløpig øktstart, løpesteg og rutinemilepæler – ikke alle Ghost-, rute-, mål- eller styrkemeldinger. Appkrasj, bakgrunnsavbrudd og lydrutebytte kan fortsatt gi tapte/dupliserte varsler, og fysisk test gjenstår.

**Avgrensning:** 2A gir *lokal* duplikatkontroll for utvalgte typer, ikke global exactly-once-garanti på tvers av enheter. Markører inneholder kun type og intervall-/steg-ID, ikke selve talemeldingen eller brukerens helsehistorikk.

### 3. Oppdagbarhet og premiumdesign — STEG 3A–3E KODE IMPLEMENTERT, VERIFISERING GJENSTÅR

- [x] Audio Coach kan åpnes fra **både enkel og avansert** styrkestart; den er ikke lenger skjult bak Avansert.
- [x] Ved enkel styrkestart bevares valgt coach-konfigurasjon gjennom lokalt opptak, invitert treningsøkt og iPad-relay, uten automatisk å aktivere øvrige avanserte treningsvalg.
- [x] Ny **Enkel / Standard / Avansert** i `ATHLTHCoachContentLevel` endrer bare innholdet i tale; distanse-/tidsintervaller, stemme, lydnivå og Watch-lydansvar forblir uendret.
- [x] Premium valg av innholdsnivå i løpingens **live Audio Coach-panel** med status for faktisk valgt nivå eller manuelt tilpasset oppsett.
- [x] Samme innholdsnivå som **persistente standardinnstillinger** med eksisterende off-white / ghost-card design. Enkelttogglene beholdes for manuell overstyring.
- [x] Enhetstester for nivåmapping og at kadens, stemme, enable-state og lydansvar ikke endres.
- [ ] Verifiser komplett iOS/watchOS-bygg og automatiske tester på samlet commit.
- [ ] Manuell QA: enkel styrke, avansert styrke, Watch-start, invitert økt, iPad-relay og eksisterende stemmevalg.
- [ ] Gjennomført coach-status og samme premiumkontroller i **alle** støttede øktstarter og på Watch; de første skjermene er nå forbedret.
- [x] Separat talefrekvens og talestil (balansert, teknisk, motiverende, minimal). Talefrekvens styres fortsatt via uendrede avstands-/tidsintervaller; talemåte påvirker kun ordlyd.
- [x] **Steg 3B:** iPhone live Audio Coach-panel har **Pause tale / Fortsett tale** og **Status nå**. Aktivitetens HealthKit/GPS-registrering, intervallterskler og øvrig varsling endres ikke av en midlertidig talepause.
- [x] **Steg 3B:** Apple Watch-kontrollsiden har tilsvarende knapper. En manuelt ønsket status kan spilles av direkte på klokken, også når iPhone normalt eier automatiske coachmeldinger.
- [x] Talepausen er eksplisitt avgrenset til **Audio Coach**: kritiske Route Guardian-/målvarsler og selvstendige Ghost-varsler beholder sine egne lydinnstillinger; haptikk påvirkes ikke.
- [x] «Status nå» bruker oppdatert øktinformasjon uten å flytte varslingsterskler eller endre øktplan; klokken avviser gammel puls.
- [x] Automatiske tester for talemute/på, uendrede intervaller og uavhengig kritisk haptikk/lyd.
- [ ] Fysisk QA av «Status nå» via AirPods/Watch, audio interruptions, Spotify, gjentatt trykk og rute-/Ghost-varsler.
- [x] **Steg 3C:** `ATHLTHCoachReplayMemory` holder kun siste ordinære coachbeskjed i RAM, og gir mulighet til «Hør igjen» i maks **45 sekunder**; slettes ved ny økt. Kritiske Route Guardian-/mål- og Ghost-beskjeder lagres ikke for reprise.
- [x] iPhone livepanelet viser siste coachbeskjed, tidsbegrenset replay-knapp, navnet på systemets aktive lydutgang når kjent, og eksisterende **Apple AVRoutePickerView** for AirPods/AirPlay/andre systemruter.
- [x] Apple Watch-kontrollsiden viser siste Watch-genererte coachbeskjed, «Hør igjen», lydutgang når kjent og veiledning til Kontrollsenter; kontrollsiden kan scrolles på små klokker.
- [x] Speilede Apple Watch-økter: iPhone-visningen viser om **iPhone eller Watch eier talemeldingene**, og siste iPhone-beskjed kan kun repeteres dersom iPhone faktisk har aktivt lydansvar.
- [x] Repetisjon endrer **ikke** automatiske distanse-/tidsintervaller og forlenger ikke utløpstiden for siste beskjed.
- [x] Tester for 45-sekundersgrense, ugyldig/fremtidig melding, nullstilling og at kritiske/Ghost-varsler ikke legges i replay-historikk.
- [ ] Manuell gjennomgang av lydutgang under Spotify/AirPods, bluetooth fra/til, bakgrunn, Live Ghost, variasjoner i Watch voice lease og lange talemeldinger. Systemrapportert lydrute er ikke en garanti for hørbar avspilling.
- [x] **Steg 3D:** egen off-white Audio Coach-kontroll i aktiv styrketrening på iPhone, med **Pause tale, Fortsett tale, Status nå og Hør igjen**; vises både ved tomt freestylebibliotek og når øvelser er valgt.
- [x] **Steg 3D:** styrkens `StrengthAudioCoachSpeaker` bruker samme tidsbegrensede `ATHLTHCoachReplayMemory` (45 sekunder), og talemute stopper ikke settføring, hviletid, HealthKit eller vibrasjoner.
- [x] **Steg 3D:** iPhone-styrkestatus sier antall fullførte sett, aktiv øvelse og fersk gjenværende hviletid. Den deles med Watch via `ATHLTHStrengthCoachStatusMessage`, med bokmål/engelsk og beskyttelse mot negative/utdaterte verdier.
- [x] **Steg 3D:** styrkecoachens oppstart aktiveres også for **enkel** styrkemodus når coachen eksplisitt er valgt; loggingen trenger ikke endres til avansert modus.
- [x] **Steg 3D:** ikke-løpe-trening på Watch (inkludert styrke) har rullbare coachknapper for talemute, fersk status og repetisjon, mens øktpause og øktslutt holdes separat.
- [x] Regresjonstester for styrkestatus, settgrenser, utløpt hvile og uavhengige stemme-/vibrasjonskanaler.
- [ ] Siste samlede Xcode-build og fysisk Apple Watch/iPhone-QA av styrketale, basic/advanced, pause/fortsett, tidsbaserte sett, rest-countdown og AirPods med Spotify.
- [x] **Steg 3E:** valgbare talemåter **Balansert, Motiverende, Teknisk og Minimal** i `ATHLTHCoachSpeechStyle`, uten AI-API, nettverkskall eller endringer i øktregistrering.
- [x] Talemåten lagres som global standard og kan overstyres for løpeøkter og styrkeøkter; beholdes gjennom Quick Start, planlagt økt, iPhone, Apple Watch og eksisterende Watch-overføring.
- [x] Valgt talemåte brukes ved faktisk AVSpeech-avspilling i **iPhone-løping, speilet Watch-løping, direkte Watch-coach og iPhone-styrke**, inkludert riktig tekst i kortvarig «Hør igjen»-historikk.
- [x] Justerbar talemåte under løpeøkt på iPhone og Watch, og ved styrkeøktstart og Watch-styrke. Global forhåndslytt bruker **fiktive** treningsdata og valgt stemme, språk, volum og hastighet.
- [x] **Kritiske Route Guardian-/mål- og Ghost-varsler endres ikke av talemåte**; motivasjon legges bare til nøytral treningsfremdrift, og minimalstil forkorter kun ord for måleenheter uten å droppe målinger.
- [x] Nye tester for fire stiler, kritiske varsler, numeriske verdier, reprisering uten doble oppmuntringer, uendrede frekvenser og bakoverkompatibel serialisering.
- [ ] Fullfør iOS-/watchOS-bygg og fysisk verifisering av gammel og ny Watch-paring, AirPods/Spotify, styrkeøkt, synkronisert duell og siste-beskjed-funksjon.
- [ ] Neste: eventuelt egen forhåndslytt inne i livepanelet og mer naturtro kontekstuelle fraser i øktplaner, mens nøyaktige målsoner og sikkerhetsvarsler forblir urørt.

**Omfang:** Innholdsnivåene gjenbruker eksisterende `WatchAudioCoachConfiguration` og krever ingen nye serverfelter eller databaseendringer. Nye avanserte treningsfunksjoner skal ikke aktiveres bare fordi et enkelt coach-nivå er valgt.

### 4. Løping og treningsplaner

- [ ] Bevar fase-type (oppvarming/arbeid/hvile/steady/nedtrapping) i Watch-transfer i stedet for friteksttittel alene.
- [ ] Neste-drag-forhåndsvarsel, nedtelling, overganger, midtveisstatus og cool-down.
- [ ] Smart Pace Coach med glattet tempo, hysterese, grace window og faktisk målsone.
- [ ] Pulssoneinstruksjoner bare ved valide, ferske sensordata + aktivt mål.
- [ ] Innendørs tredemølle uten falsk GPS-rute; høydedata bare når støttet.
- [ ] Bruker skal kunne legge inn coach-mål i en planlagt økt og endre det underveis.
- [x] Manuell «Gi meg status nå» for iPhone-registrert løping og Apple Watch-økter.
- [ ] «Siste coach-beskjed» / replay med riktig historikk og lydutgang.

### 5. Styrke, pauser og tidsbaserte sett

- [ ] Settmål, reps/vekt, oppvarmingssett, supersett, sirkeltrening, nestemann.
- [ ] Én timer for styrkesett og talte nedtellinger – identisk på alle skjermflater.
- [ ] Hvile forleng/pause/hopp over uten falske timer-meldinger eller automatisk steghopp.
- [ ] Fornuftig antall meldinger og prioritet når sett fullføres under pågående tale.
- [ ] Fullt live kontrollpanel for iPhone/Watch; bruk samme event engine.

### 6. Ghost, Route, Arena og Trene sammen

- [ ] Ghost-meldinger basert på stabil fremdrift, uten GPS-jitter-spam.
- [ ] Ruteavvik, tilbake på rute og siste del av ruten med riktig prioritet.
- [ ] Arena-duellhendelser, reell fremdrift og sluttspurt – kun når dataene kan dokumenteres.
- [ ] Fysisk sammen / samme økt: individuell privat coaching og felles plan der det er hensiktsmessig.
- [ ] Ingen lekkasje av privat hjertefrekvens, treningsdetaljer eller personlig informasjon til andre deltagere.

### 7. Personlig tilpasning, timeline og debrief

- [ ] Coach Timeline: siste/kommende melding, gjenta lyd, logg over droppede/utsatte varsler.
- [ ] Lokal Coach Memory for eksplisitte preferanser og kontroll for å nullstille dem.
- [ ] Adaptive Coaching etter treningsfase, varsomhet og valgte frekvensinnstillinger.
- [ ] Oppsummering etter økt med *målebaserte*, etterprøvbare observasjoner.
- [ ] Valgfri AI/coaching-samtale **senere**: eksplisitt samtykke, målrettet datautvalg, GDPR-vurdering, offline fallback.

### 8. Akseptansetester og utrulling

- [ ] Automatiserte tester: prioritet, duplikater, konkurrerende hendelser, stilleperioder, mål og grenser.
- [ ] Integrasjon: iPhone, Watch alene, Watch+telefon, omstart/recovery, nett frakoblet.
- [ ] Fysiske tester: lydrutebytte, Spotify, AirPods, iPhone-høyttaler, Watch-høyttaler, pause og intervallskifte.
- [ ] Tilgjengelighet: VoiceOver, dynamisk tekst, haptikk, lokalisering norsk/engelsk.
- [ ] Mål kvalitet: manglende/dupliserte meldinger, feil intensitetsvarsler, prosent som deaktiverer coaching.
- [ ] TestFlight **bare** når bruker ber uttrykkelig om opplasting.

## Arbeidsregler

- Ikke merk et steg som ferdig kun fordi kode er skrevet. Oppgi commit, bygg- og teststatus hver gang.
- Behold eksisterende forutsigbar atferd med migrering av eldre `Codable`-verdier og trygge defaults.
- Nye funksjoner skal kunne deaktiveres, og plan/HealthKit-opptak må fortsette ved lydfeil.
- Bruk dette dokumentet som fremdriftsliste i senere samtaler; fortsett med første utestående, avgrensede leveranse.
