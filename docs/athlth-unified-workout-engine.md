# ATHLTH: én planleggingsmotor, tilpassede live-motorer

Status: 1.9.1 – planprosjeksjon, UI-ruting og begrenset fellesopptak for planlagt styrke + tidsstyrt tredemølle er koblet inn i kalendervisningen. Kode-/simulatortester er satt opp; fysisk Watch-verifikasjon gjenstår.

## Ett felles øktoppsett

Alle innganger (Plan, Planlegg ekstra økt, Quick Train, lagrede maler og Tren sammen)
skal produsere den samme konseptuelle øktoppskriften:

- Identitet: én PlannedSession.id for hele økten
- Kronologisk struktur: WorkoutTemplateBlock, phase (warmup/main/recovery/cooldown)
- Løpeintervaller: RunningWorkoutTemplate beholder kildemal, repetisjoner,
  pauser, pulssoner, fart og individuelle dragjusteringer.
- Styrke: PlannedExercise beholder sett, vekt, reps, tid og pauser.
  workoutPhase velger om øvelsen er oppvarming, hoveddel eller nedtrapping.
- Kompatibilitet: ATHLTHUnifiedWorkout.editorBlocks(...) lager en ikke-destruktiv
  kronologisk visning av eldre/parallelle modeller. Eksisterende lagrede økter
  og invitasjoner skal fortsatt dekodes uten datamigrering.

Målet er at workoutBlocks etter kontrollert migrering blir primær kilde.
Aldri spill av både utledede blokker og originalmal som to separate økter.

## Live-ruting: plan styrer motoren

ATHLTHLiveWorkoutEngineRouter klassifiserer hvert trinn:

| Trinn | Motor | Relevante data |
| --- | --- | --- |
| run | endurance | tid, distanse, tempo, puls, intervall, rute |
| exercise | strength | øvelse, sett, reps, vekt, RPE/RIR |
| rest | recovery | pausetid, neste trinn |
| note med wellnessKind | mobility | tid og instruksjoner |
| note | instructions | instruksjon |

Overgangen mellom trinn må bevare PlannedSession.id, samlet tidslinje og
opptaksidentitet. Et bytte av kort eller motor er **ikke** autorisasjon til
å starte en ny HealthKit-trening eller lagre en egen treningsøkt.

## Delvis aktivert opptak (1.9.1)

`ATHLTHHybridWorkoutLaunchPlan` validerer hele planen *før* start.
For en planlagt kalenderøkt med både styrke og tidsstyrte
tredemølleblokker lager den en faseordnet serie som sendes til
`StrengthWorkoutStore.startPlannedHybrid`. Den eksisterende
`StrengthWorkoutStore` eier opptaket og bytter internt mellom styrkesett og
innebygde løpeintervaller, med samme `plannedSessionID` og `watchSessionID`.
Én start på Apple Watch bruker foreløpig HealthKit-styrketype og blir
derfor **ikke** en fullverdig GPS-/løpe-HealthKit-motor.

Ustøttede kombinasjoner, som GPS-ruter eller distansebaserte drag, avvises
fremfor å starte en run-only-økt og miste styrkedelen.

Testjobber (ingen TestFlight-opplasting):
- `.github/workflows/launch-smoke.yml` – iPhone simulator build/launch
- `.github/workflows/hybrid-engine-tests.yml` – målrettede XCTest-suiter

## Apple Watch: tidsstyrt hybrid i 1.9.1

For en **validert innendørs styrke + tidsstyrt tredemølleøkt** forblir
`WatchWorkoutManager` eier av **én** løpende HealthKit-styrkeøkt.
En ny `ATHLTHHybridWatchIntervalPolicy` lar Watch fullføre og gå videre
til neste tidsstyrte løpefase når planlagt tid er utløpt, uten å be iPhone
starte ny økt. iPhone mottar setthendelser via eksisterende
`WatchStrengthCommand`-journal og lagrer resultatet i samme
`StrengthWorkoutLog` med uendret plan- og Watch-identitet.

Watch-køen inneholder mål for hvert drag (varighet, fase, puls-sone,
måltempo). Manuell møllefart og estimert distanse behandles fortsatt
**ikke** som sensorbasert måling. Pause/gjenoppta på Watch stopper også
den aktuelle fasens nedtelling; ved sein levering bruker iPhone
hendelsestidspunktet fra Watch.

Sikkerhetsgrenser:
- Watch avanserer ikke reps-baserte styrkesett automatisk.
- Watch avanserer ikke hybrid-timer ved pauset HealthKit-økt eller når
  økten styres i «kun iPhone»-modus.
- Overgang til en annen øvelse er fremdeles en bevisst handling.
- Sammenkoblede GPS-/distansebaserte løp og styrke er fortsatt ikke
  støttet gjennom denne innendørsmotoren.
- Et fullstendig nytt HealthKit-opptakssystem for vilkårlig bytte mellom
  alle idretter/motorer er **ikke** implementert.

Regresjonstester dekker Watch-preskripsjon, intervalldriver, pause-
og gjenoppta-klokke, samt samlet opptaksidentitet. CI bygger både
målrettede iPhone-simulatortester og et separat Watch-simulatormål.
**Fysisk Watch-verifikasjon og reelle bortfall av forbindelse gjenstår**
før en hybridrelease kan anses endelig godkjent.

## 1.9.1 – Watch-hybrid kobling (implementert i kode, fysisk test gjenstår)

- **Én aktiv HealthKit-økt**: planlagt styrke og tidsstyrte innendørs
  tredemøllefaser deler Watch-opptaket og samme parent workout-ID.
  Watch-treningen er fortsatt kategorisert som tradisjonell styrke, ikke
  en selvstendig GPS-løpeøkt.
- **Én klokke som eier automatiske faseoverganger**: for Watch-opptak
  med Watch/begge som inndata håndterer Watch ferdigstilling av løpedrag.
  iPhone forsøker ikke samtidig å fullføre det samme draget. Ved iPhone-
  styrte eller iPhone-opptatte økter brukes iPhone-klokken.
- **Pause og gjenoppta**: Watch journalfører handlingene med hendelsestid,
  slik at iPhone kan rekonstruere nedtellingen etter brudd i forbindelse.
  Også systemutløste HealthKit-pauser behandles.
- **Fasedetaljer**: tittel, type, planlagt varighet, pulssone og måltempo
  følger med til Apple Watch, og oppdateres ved fasebytte. Måltempo er
  aldri deklarert som målt fart.
- **Målt distanse**: under innebygde møllefaser kan Watch abonnere på
  faktiske `distanceWalkingRunning`-samples. Hvis HealthKit ikke leverer
  disse under et styrkeopptak, forblir den målte distansen ukjent; appen
  skal ikke erstatte den med fart × tid uten å merke estimatet.
- Automatiske XCTest-regresjoner og watchOS-simulatorbygg kontrollerer
  koden; **fysisk Apple Watch-akseptansetest er fortsatt et eget krav**.
  Ikke dokumenter dette som fullført sensorbasert universal-motor.

## Fremtidig sensor- og opptakskoordinator (ikke implementert)

Én sentral runtime-koordinator skal eie:

1. én stabil workoutID, opptaks-ID, starttid og pause-/gjenoppta-status
2. én HealthKit-/Watch-opptakslivssyklus; ingen duplisert workout ved motorbytte
3. per-segment rådata og måleproveniens (Watch/målt, manuelt eller estimert)
4. registreringsstatus, offline lagring, gjenoppretting og klokkesynk
5. endelig én oppsummering, historikk- og fremgangspost, med segmentvis drilldown

Løpemotoren og styrkemotoren skal være adaptere som *forbruker* samme
runtime-koordinator og deler sensorstrømmen, ikke to uavhengige start/stop-motorer.
Apple Watch-støtte for en blandet trening skal avklares og testes før aktivering;
planlegging er ikke dokumentasjon på at sensorkoblingen virker.

## Utrullingskriterier

1. Plan/preview viser riktig rekkefølge for oppvarming → 4×4 → styrke → nedtrapping.
2. 4×4 beholder nøyaktig 4 drag og 3 mellompauser, inkludert per-drag mål.
3. Et blokkskifte gir riktig live UI, uten å nullstille samlet tid.
4. Ett målt treningsopptak og én treningshistorikkpost etter fullført hybridøkt.
5. Ingen dobbeltregistrering i Apple Health eller egne prestasjoner.
6. Ingen ekstra GPS ved innendørsmølle; manuell fart merkes separat fra målt data.
7. Økten kan fortsette etter kortvarig frakobling, telefonskjermlås og Watch-restart.
8. iOS/watchOS regresjonstester før TestFlight.

Dette dokumentet beskriver arkitektur og krav. Det er **ikke** en påstand om
at sensorbasert hybridmotor eller automatisk Watch-overgang er ferdig.


## 2.2.5 — ny felles motor: gjennomføringsplan og oppryddingslogg (18.11.2026)

Den eldre 1.9.1-beskrivelsen over er bevart som historikk. Dette er den aktive
migreringsplanen for styrke og løping på `release/v2.2.5`. Gjennomfør endringene
**direkte på release-grenen**, fasevis, uten en annen parallell opptaksmotor.

### Fase 1 — fundament (kode lagt inn; iOS/Watch-bygg må verifiseres)

- `ATHLTHWorkoutSessionClock`: én absolutt datobasert klokke for aktiv løping,
  styrkesett og nedtelling. Gammel duplisert tidsmatematikk er erstattet på
  de eksisterende kodebanene. Den må tåle skjermlås, pauser og overtid.
- `ATHLTHWorkoutSessionFoundation`: én normalisert, **avledet** visning av
  aktiv økt-ID, plan-ID, registreringsansvar (iPhone/Watch), fase, motor,
  framdrift og faktisk tid. Verdiene leses fra `PhoneWorkout` eller
  `StrengthWorkoutLog`; de journalføres ikke dobbelt.
- Felles policy for gjenoppretting: et aktivt sjekkpunkt skal ikke reaktiveres
  når avslutningen allerede er lagret i historikken.
- Oppstart av løping, gåing og styrke avviser en ny start i samme lokale motor
  mens den motoren allerede har en aktiv/restituert økt. Planlagt styrke og
  fri styrke skal aldri kunne overskrive et eksisterende aktivt styrkesett.
- `ATHLTHLiveWorkoutEngineRouter` bruker samme økt-ID-policy ved fasebytte.
  Ingen ny HealthKit-økt startes når bare livevisningen bytter motor.
- Nye tester: `ATHLTHWorkoutSessionFoundationTests`; eksisterende tester for
  Watch, styrkesett, hybrid, kontinuitet, klokker og historikk beholdes.

**Avgrensning:** Fase 1 samler kontrakter, klokker og kontrollregler; den
erstatter *ikke* ennå alle opptaksimplementasjonene med én fysisk HealthKit-
koordinator. Global gjensidig sperre mellom alle opptaksveier, GPS-hybrid,
automatisk live-UI-overgang og nye Watch-styringskommandoer må ikke markeres
som ferdige før egne faser og reelle tester er fullført.

### Faser 2–8 (vent til forrige fase er verifisert)

2. Felles fast bunnkontroll for løp/styrke, men behold styrkens media-/øvelseskort.
   La arbeid, hvile og overgang ha egne tilstander. Slett først det gamle
   `compactLiveStrengthDock` og gammel selvstendig løpe-bunnkontroll **når**
   én ny kontroll faktisk brukes fra begge livevisninger og har bestått tester.
3. Avanserte sett/øvelser: RPE/RIR, vektskiver/stang, tid, motstand, warmup,
   supersett, sirkel, EMOM, AMRAP og dropsett; bevar stabile sett-/øvelse-ID-er.
4. Watch + iPad: synk, kommando-ID/idempotens, offline journal og samtykkebasert
   livevisning. Utvid opptakskoordinatoren stegvis med én aktiv HealthKit-eier.
5. Audio Coach: samordne eksisterende trigger-/kommando-regler med felles
   tids- og fasehendelser, uten ekstra stemmer eller dobbelt tale.
6. Live Activity/Widget/Dynamic Island: del samme fase-/klokkekilde og test
   låseskjerm, telefonlås, avbrudd og sen Watch-status.
7. Samlet resultat/HealthKit: én historikkpost/HealthKit-workout, med
   segmentvise mål, korrekt arbeidstid/hvile og PR-evidens.
8. Full regresjon og ytelse: iPhone, iPad, Apple Watch, skjermlås, Spotify,
   HealthKit, gamle treningsplaner og lange aktive styrkeøkter.

### Sletting og migrering — obligatorisk regel

- **Erstatt → test → slett**, aldri slett aktiv opptaks-, synk- eller
  historikklogikk bare for å «rydde» før erstatningen er bevist.
- Fase 1 fjernet overlappende regne-/gjenopprettingslogikk på kodebanene,
  men **beholdt** historiske `PhoneWorkout`, `StrengthWorkoutLog`,
  `StrengthTimedSetCountdown` og `StrengthSetEffortClock` for kompatibel
  dekoding av tidligere lagrede sjekkpunkter.
- Fase 2 rydder bort de gamle bunnkontrollene etter at nye er operative.
  Fase 3–7 fjerner utgåtte lokale statuskopier, dupliserte eventhåndterere
  og ubrukte modeller etter at alle oppslag/migreringer er kontrollert.
- Ingen sletting av brukernes historikk eller original-HealthKit-poster.
  Kontroller at aktive økter etter appstart ikke blir fullført eller erstattet
  uten brukerhandling. Test overgang til nytt skjema med gamle JSON-filer.
- Hver fase får egne tester, konkret kodegjennomgang, CI-status og
  oppryddingsdiff før vi starter neste fase.


### Fase 2 — felles bunnkontroll (kode implementert, verifisering pågår)

- `ATHLTHLiveWorkoutBottomMode` beskriver klart én primær handling per fase:
  start hoveddel, neste drag, legg til intervall, start sett, fullfør sett,
  start neste sett, neste øvelse, legg til styrkeøvelse og avslutt økt.
  Rest +30 sekunder er en sekundær handling.
- `ATHLTHLiveWorkoutBottomDock` brukes av både
  `IPhoneWorkoutView.runningNextControl` og
  `ActiveStrengthWorkoutView.strengthLiveDock`. Den viser samme faste
  bunnflate, primærknapp, valgfrie sekundærknapper og valgfritt
  aktivitetsspesifikt datainnhold.
- Styrkens eksisterende liveøvelseskort, øvelsesbilde, instruksjoner,
  volum, motstandsnivå, vekt inkl. stang/skiver, repetisjoner og
  tidtaking er beholdt. Alle settdata skrives fremdeles bare gjennom
  `StrengthWorkoutStore` og den autoritative økt-ID-en.
- En hvileperiode slutter først når brukeren velger «Start neste sett»;
  `+30 sek` forlenger hvilen. Tidsbaserte sett starter nedtelling på
  neste sett, men når ikke «fullført» uten eksplisitt brukerhandling.
- Neste øvelse tilbys i den faste bunnflaten først når alle sett er
  fullført eller bevisst hoppet over via eksisterende bekreftelsesflyt.
  Ingen manglende sett markeres utført ved øvelsesbytte.
- **Slettet faktisk ubrukt kode:** den gamle styrkesatte
  `compactLiveStrengthDock`, den gamle løpeknappen nederst og
  `focusedSetEntry` (ubrukt alternativ visning med ekstra
  «Fullfør sett»-knapp). Ingen modell-/historikkmigrering er utført.
- Spesialtilfellet *løpeintervall inne i styrke* beholder sin
  tidligere kontrollerlogikk foreløpig. Watch-styrt setregistrering
  beholder eksisterende tillatelser; den nye iPhone-bunnflaten blir
  ikke en alternativ skrivetilgang til en Watch-styrt økt.
- Nye tester: `ATHLTHLiveWorkoutBottomModeTests` inngår i målrettet
  hybrid-test og full XCTest. Sjekk full iOS, watchOS, iPhone/iPad-
  kompatibilitet, skjermlås, frie styrkeøkter, komplette økter,
  tids- og vektbaserte sett før fase 2 godkjennes.
- **Ingen ny TestFlight-opplasting**, og fase 3 er ikke startet.

- Etter siste sett i en øvelse kan pausen fortsatt telles ned i den samme
  bunnflaten. «Neste øvelse» går videre uten å fullføre uregistrerte sett,
  mens «+30 sek» utvider faktisk hvile. Dette er ikke samme handling som
  «Start neste sett» midt i en øvelse.


### Fase 3 — avanserte styrkesett (første del, bygg/verifisering pågår)

- Eksisterende `StrengthWorkoutStore`, `StrengthSetLog` og
  `StrengthAdvancedConfiguration` beholder eierskap til sett, RPE/RIR,
  oppvarming og timer. Ingen ny opptaksmotor eller dublerte settmodeller.
- Felles live-bunnfelt viser den konfigurerte *én* innsatsmålingen (RPE
  **eller** RIR, aldri begge) samt oppvarmingsvalg i Advanced. Resultatet
  skrives gjennom eksisterende `setDraft` og `completeCurrentDraftSet`.
- Tidsbaserte sett justeres nå direkte i sekunder (15 sek per hurtigtrykk);
  dette unngår avrunding til minutter for 15/30/45 sekunder.
- Gruppetypen og stasjonsnummeret vises i samme bunnfelt, men EMOM/AMRAP
  beholder sin eksisterende autoritative gruppetimer og grensekontroller.
- Barbell-/skivematematikk, motstandsnivå, sett-ID og Watch-overføring er
  uendret og må bestå eksisterende regresjoner.
- Nye regresjonstester verifiserer RPE/RIR, faktisk oppvarmingsmerking,
  eksakt settid og bevaring av økt-/øvelse-/sett-ID-er. Full fase 3
  omfatter også gjennomgang av gruppemodus og overgangskontroller før
  endelig godkjenning.

- **Fase 3 / gruppemodus – EMOM-sikring:** Et tidsvindu som er hoppet
  over beholdes i den opprinnelige sett-ID-en med `skippedAt`. For
  historiske EMOM-sjekkpunkter er `skippedPlannedSetCount` en
  speilregistrering av samme hendelse, derfor brukes maksimum av de to
  tellerne i rapporteringen – ikke summen. Dette hindrer at en manglende
  stasjon telles dobbelt.
- Eksisterende `completeCurrentSet` og `skipCurrentSet` avviser nå et
  allerede **løst** sett (`isResolved`), både ved dobbeltrykking og
  gjentatte/sene Watch-kommandoer. Å hoppe over et EMOM-sett stopper den
  lokale innsatstimeren uten å fullføre eller opprette et nytt sett.
- Regresjonstester kontrollerer at gjentatt skip og forsøk på å fullføre
  et utelatt EMOM-sett ikke endrer økt-ID, sett-ID eller volum, at den
  historiske telleren overlever JSON-rundtur, og at gruppemodusene fortsatt
  fungerer gjennom felles styrkemotor.

- **Fase 3 / gruppeprogresjon:** Et bevisst hoppet-over sett i supersett,
  sirkel, dropsett og AMRAP beholder nå sin opprinnelige stasjon,
  runde og sett-ID akkurat som EMOM. Dette unngår at resterende øvelser
  forskyves og blandes med neste runde. Den eksisterende
  `advanceGroupedSetIfNeeded` velger neste stasjon; ingen ekstra motor,
  HealthKit-økt eller settmodell opprettes.
- Watch- og historikkkompatibilitet beholdes ved at den opprinnelige
  skipped-telleren fortsatt oppdateres. `auditedSkippedSets` skiller
  speilet skip-tall fra faktiske ekstra utelatte sett, også i
  andre gruppemoduser enn EMOM. Testene kontrollerer faste sett-ID-er,
  ett skip, null utført volum og riktig neste stasjon.

- **Fase 3 / Watch og valg av neste steg:** Watch-snapshot og manuell
  øvelse-/settvelger bruker nå `isResolved` for å finne neste åpne sett,
  slik at et bevart gruppesett med `skippedAt` aldri tilbys for registrering
  på nytt. Overgangen «Neste øvelse» godtar også en gruppe som ble
  uttrykkelig avsluttet ved å hoppe over siste sett (`completedAt`), uten
  at manglende repetisjoner telles som utført. Egne regresjonstester dekker
  både sperre mot gjenvalg og faktisk overgang til neste øvelse.

- **Fase 3 / sikre start/hvile-overganger:** `StrengthWorkoutStore`
  krever nå et uløst sett og et gyldig gruppe-tidsvindu før «Hopp over
  pause / start neste sett» gjør noe. Hvis EMOM-minuttet ennå ikke er
  tilgjengelig, beholdes den opprinnelige pausefristen og settklokken
  startes ikke. Tidsbaserte sett kan heller ikke starte nedtelling mens
  hvile fortsatt er aktiv.
- Et avslått «Neste øvelse»-forsøk forandrer ikke hvilestatus.
  Ved automatisk EMOM-overgang til en ny øvelse nullstilles gamle
  gruppe-/setttimere, og første **uløste** sett velges – aldri et
  hoppet-over eller fullført sett. Alle handlingene bruker samme
  `StrengthWorkoutStore`, uten duplikat-HealthKit eller ny klokke.
- `ATHLTHStrengthGroupedSetTests` er utvidet med verifisering av
  blokkert tidlig EMOM-start, bevart hviletid, tidssett under hvile og
  opprydding av klokker ved automatisk gruppeslutt.

- **Fase 3 / forsinket Apple Watch-synk:** Watch-kommandoer for
  hopp over pause og +30 sek sender nå også opprinnelig øvelse- og
  settindeks. iPhone avviser en gammel rest-kommando dersom den gjelder
  en annen stasjon eller ble sendt før den aktive pauseperioden startet.
  Eldre kommandoer med valgfri/manglende indeks kan fremdeles dekodes.
  Kommandoer mot allerede fullførte/hoppede sett ignoreres før noen
  kladdeverdier kan overskrives.
- **Korrekt tidsstempel:** Live og offline Watch-settfullføring, pause,
  pauseforlengelse og overgang til neste øvelse bruker hendelsens
  `sentAt` i den eksisterende `StrengthWorkoutStore` i stedet for
  tidspunktet Bluetooth-meldingen ble mottatt. Dette gjelder også
  faktisk settid, fullført-tid og faktisk hvile etter settet.
- **Watch-totalsum:** Sett som er beholdt med `skippedAt` i
  supersett/sirkel/EMOM/dropsett/AMRAP blir nå telt én gang i
  `WatchStrengthSessionSnapshot.totalSets`. Bare fysisk fjernede
  planlagte sett legges til via den gamle skipped-telleren.
  Nye tester dekker totalsett, feil stasjon, gammel pause og etterpå-
  mottatte klokkeslett; ingen ny klokke, historikkmigrering eller
  HealthKit-økt er introdusert.

 
### Fase 4 — iPad-samtykke og Watch-journal (første del)

- iPad-forespørsler skal nå være sendt under **den aktuelle
  treningsøkten**, for riktig konto og fortsatt være ventende. Gammel
  forespørsel fra en avsluttet økt kan ikke godkjenne en ny.
  Asynkrone svar fra Supabase verifiserer konto og økt på nytt før
  forespørselen vises eller godkjennes.
- Watch-kommandoer som **endrer** et treningsopptak må bære
  nøyaktig aktiv `workoutID`. Legacy-kommandoer uten
  trenings-ID kan dekodes, men ikke endre en tilfeldig ny økt.
  Den eksisterende offline-journalen sorteres deterministisk og
  håndterer hver kommando-ID maksimalt én gang per replay.
- Én eksisterende styrkemotor og én HealthKit-eier beholdes. Dette
  er første sikkerhetsdel av fase 4, **ikke** en påstand om ferdig
  end-to-end iPad-/Watch-synk, fysisk test eller global
  HealthKit-koordinator på tvers av alle idretter.

- **Fase 4 / ytterligere idempotens:** En egen, øktavgrenset
  replay-UUID-vakt hindrer at samme offline Watch-kommando kjøres
  på nytt i en senere batch mens appen er åpen; den nullstilles når
  økt-ID-en skifter. Mottakerens eksisterende vedvarende journal
  for håndterte UUID-er beholdes også lenger for langsom levering.
  Begge har begrenset størrelse og endrer ikke HealthKit-opptaket.
- Privat, lesbar iPad-styrkestatus teller beholdte gruppesett med
  `skippedAt` nøyaktig én gang, både totalt og per øvelse.

- **Fase 4 / Watch-opptakseier etter kontobytte:** Hvert nytt
  `WatchStrengthCommand` merkes nå med kontoen som eide den aktive
  Watch-treningen ved oppstart. En Watch-startet styrkeøkt kan kun
  gjenopprettes automatisk på iPhone hvis den innloggede kontoen,
  økt-ID-en og eventuelt bootstrap-snapshot har matchende eierskap.
  Legacy-kommandoer uten eier-ID dekodes fortsatt, men kan ikke
  opprette en ny styrkeøkt på en vilkårlig konto. Den opprinnelige
  Watch-journalen og fullføringsresultatet beholdes på Watch.

- **Fase 4 / innlogging og frakobling:** Ventende Watch-kommandoer
  filtreres nå etter eierkonto før de forbrukes fra den vedvarende
  journalen. En annen kontos kommando bevares, men kan ikke mutere
  den aktive økten. Kommandolisten forsøkes på nytt ved innlogging,
  kontobytte og når øktsjekkpunktet er gjenopprettet. Eldre Watch-
  kommandoer uten eier-ID kan fortsatt brukes mot en **eksakt
  eksisterende** aktiv økt med samme UUID, men ikke starte en økt.
  Oppstartsforespørsler med feil/manglende eier beholdes i køen
  for senere kontroll i stedet for å bli kvittert ut feilaktig.

- **Fase 4 / ikke opprett tom erstatningsøkt:** En frakoblet
  Watch-forespørsel må dessuten inneholde den originale
  `WatchStrengthSessionSnapshot` med **samme workoutID**.
  Den gamle fallbacken som kunne starte en ny tom freestyle-økt
  med en annen UUID er fjernet. Ufullstendige forespørsler beholdes
  ubehandlet for sikker gjenoppretting, uten å produsere falske
  treningsresultater.

- **Fase 4 / iPad-gjenoppkobling og stale data:** iPad oppdaterer ikke
  lenger livekort fra asynkrone Supabase-svar dersom kontoen ble
  endret under forespørselen. Også innkommende
  godkjennings-/tilgangsstatus blir avvist etter kontobytte.
  Tidsstempelpolicyen krever gyldig, ferskt heartbeat,
  utløpstid og (når kjent) fersk `capturedAt` fra Watch/iPhone.
  En gammel Watch-snapshot kan derfor ikke bli fremstilt som live
  bare fordi iPhone fortsatt sender heartbeat. Eldre payloads uten
  `capturedAt` kan fremdeles vises når server-heartbeat er ferskt.
- iPad er fortsatt **read-only** og starter aldri et HealthKit-opptak.
  Ny `ATHLTHiPadLiveWorkoutTests` dekker frakoblet sensor,
  gammelt heartbeat, utløpt tillatelsessnapshot og eldre payloads.

### Fase 4 — samtidige asynkrone oppstarter (implementert; CI gjenstår)

- `ATHLTHWorkoutRecordingArbiter.reserveLaunch` låser midlertidig oppstart
  på tvers av Quick Run, Quick Walk og planlagt styrke. Låsen beholdes gjennom
  `await` ved Watch-/sosial-/iPad-overlevering og frigjøres ved både suksess
  og feil. Den er ikke et nytt opptak eller et ekstra HealthKit-objekt.
- Flere samtidige startforsøk kan ikke begge passere innledende kontroll
  før første oppstart har sluttført sin asynkrone sekvens. Et gammelt
  avslutningskall kan ikke frigjøre en nyere start.
- Etter Watch-oppstart sjekker planlagt styrke også at en løpe-/gåøkt
  ikke har blitt aktiv i mellomtiden, før øktstatus oppdateres.
- `ATHLTHWorkoutSessionFoundationTests` dekker reservasjon, feilaktig
  frigjøring, ny reservasjon og aktiv styrkeøkt. Dette verifiserer ikke
  fysisk Watch, iPad, samlet HealthKit-eierskap eller full fase 4–8.

### Fase 4 — kontroll av pågående GPS-tillatelse og relé

- Et utendørs iPhone-opptak som venter på posisjonstillatelse, opptar
  treningsplassen til samtykke er håndtert. Nytt startforsøk kan ikke
  erstatte den ventende konfigurasjonen. Avslag fjerner ventende data.
- Planlagt styrke kontrollerer status igjen etter sosialt nettverkskall.
  Feil ved iPad-relé ruller tilbake invitasjonsoppstart.
- Apple Watch får ikke meldingen «aktiv iPhone-økt» før den faktiske
  `PhoneWorkout` finnes. Planlagt styrke markeres først startet når
  den autoritative styrkeloggen faktisk er opprettet.
- Ingen ekstra HealthKit-økt, gammel historikk eller separat styrkemotor.
  Full iOS-/watchOS-/iPad-regresjon og fysisk test gjenstår.

### Fase 5–6 — rekkefølge i Watch-snapshot og talerett (påbegynt)

- `ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot` brukes nå før
  speilstatus, Audio Coach, stemmeleie og Live Activity oppdateres.
  Forsinket melding med eldre `capturedAt`, forskjellig aktivitet eller
  annet oppstartstidspunkt avvises. Fullført økt kan ikke gjenåpnes av
  en senere aktiv-melding.
- Innkommende Watch-batcher velger nyeste gyldige opptakstidsstempel
  i stedet for siste dekodede element. Hendelses-/talekvitteringer
  fra forkastede batchelementer kan dermed ikke flytte taleretten
  ved forsinket levering.
- Dette er et sikkerhetssteg, ikke ferdig fase 5 eller 6. Fysisk
  Watch/AirPods/Spotify og widget-regresjon gjenstår.

### Fase 6 — låseskjerm og Dynamic Island: eldre status skal ikke vinne

- Speilet HealthKit-økt i tilstanden `ending` kan ikke gjenåpnes
  med forsinket `running`, `paused` eller `preparing`. Nyere
  sluttstatus kan fortsatt nå frem og avslutte riktig.
- ActivityKit-kontrolleren husker nå siste faktisk aksepterte
  `capturedAt` for samme økt. En eldre pakke kan ikke oppdatere
  låseskjerm/Island etter en nyere pakke, selv ved 5-sekunders
  oppdateringsbegrensning. En ny økt får sitt eget klokkevannmerke.
- Tester dekker nyere/eldre pakker, neste økt og ugyldig tidspunkt.
  Dette verifiserer ikke automatisk faktisk låseskjerm på iPhone.

### Fase 7 — avslutningstid fra virkelig brukerhandling

- `StrengthWorkoutStore.finish` bruker nå samme lokale `finishDate`
  for avslutning av faktisk pause og lagret sluttidspunkt, i stedet
  for å bruke et eldre gjenopprettingssjekkpunkt som sluttidspunkt.
  Det eksisterende historikkformatet og stabil økt-ID beholdes.
- Felles policy hindrer negativ varighet ved justert systemklokke.
  Testene verifiserer korrekt tidsstempel og lagret resultat.
  Samlet HealthKit-resultat/-PR og fysisk enhetsverifisering gjenstår.

### Fase 4 — fjernstart og iPad-konsistens (19.11.2026, delvis implementert)

- ATHLTHWorkoutRecordingArbiter reserverer en transient startplass før
  asynkron preflight for løping, gåing og styrke; eksisterende PhoneWorkout og
  StrengthWorkoutLog er fortsatt autoritative opptak. En reservasjon er ikke
  en ny HealthKit-økt eller en vedvarende offline-kommando.
- iPad-livevisning har sekvensvern for overlappende nettverkslesninger,
  kontooverganger og eldre snapshots fra samme økt. Eksisterende
  øktspesifikt samtykke er beholdt; dette er ikke en ny generell deling.
- iPad til iPhone/Watch-fjernstart serialiserer behandling av kommandokøen,
  validerer avsender/mål/aktivitet/dataversjon/utløp før start og drenerer
  en større kø etter frakobling. Serverkrav om client_request_id og claim
  er bevart. Statusoppdatering er avgrenset til innlogget konto
  og enheten som gjorde claim.
- Feil ved serverkvittering etter vellykket HealthKit-start behandles
  som startet med bekreftelse ventende, ikke som en mislykket start.
  En claimet kommando skal ikke startes på nytt fordi kvitteringen mangler.
  Serverbasert rekonsiliering av ukvitterte kommandoer og reell Watch-restart
  er fortsatt ikke verifisert.
- Regresjonstest for avvisning av ugyldig/utløpt kommandokonvolutt er lagt
  til ATHLTHWorkoutSessionFoundationTests. Fysisk iPhone + Watch + iPad,
  nettverksbrudd og samme-commit grønne CI-jobber gjenstår før fase 4 kan
  godkjennes. Ingen TestFlight på dette grunnlaget alene.

### Fase 5 – Audio Coach: kvitter først etter faktisk avspilling

- Styrkens Audio Coach bruker nå samme leveringsprinsipp som den
  speilede løpemotoren: en hendelse kvitteres først ved bekreftet
  start av Azure-avspilling, lokal AVSpeech-start eller vellykket
  lokal fullføring. Ikke når forespørselen er sendt.
- Forsinkede Azure-svar filtreres med øktens/gjeldende avspillings
  generasjon, aktiv lydtilstand og utløpstid. Pause, stopp og kritisk
  nedtelling ugyldiggjør eldre svar uten å registrere en falsk melding.
- Talehistorikk og «spill siste melding» oppdateres først når stemmen
  faktisk begynner. Gjenopprettbart opptak, HealthKit og haptikk
  påvirkes ikke av internettfeil.
- Felles kø avgjør lik prioritet med stabil FIFO også når flere
  meldinger har nøyaktig samme tidsstempel. Tester inkluderer
  identiske tidsstempel og sammenslåing av styrkepause-beskjeder.
- Endringen krever iOS/Watch-byggetest og lydtest med AirPods og
  musikk på fysisk enhet; ingen påstand om fullført fase 5.

### Fase 7 – også riktig sluttid for iPhone-løp og gåing

- `IPhoneWorkoutStore.finish()` sluttfører nå med faktisk
  brukerhandlingstid, ikke gjenopprettingssjekkpunktet fra før
  appavbrudd. Tid brukt mens en gjenopprettet økt er pauset
  forblir ekskludert fra aktiv tid ved hjelp av den eksisterende
  `PhoneWorkout.elapsed(at:)`-klokken og pauseintervallene.
- Regresjonen dekker både løp og gåing etter en lang bakgrunnspause.
  Ingen separat HealthKit-motor, migrering eller ny historikk-ID.

### Fase 8 – iPhone-gjenoppretting uten tidsinflasjon

- Ved rekonstruksjon av en iPhone-eid styrkeøkt stoppes nå
  tidsstyrte sett og faktisk settinnsats på det sist varig
  lagrede `Checkpoint.savedAt`. Tid utenfor appen etter prosessavbrudd
  telles ikke som utført øvelse.
- En aktiv hvile avsluttes ved samme sjekkpunkt. Registrert
  hviletid frem til sjekkpunktet bevares, men offline-tid
  legges ikke til som virkelig hvile.
- De samme nedtellingsreglene brukes ved ordinær pause og
  krasjgjenoppretting; overtid (negative gjenværende sekunder)
  beholdes. Watch-eide økter berøres ikke, ettersom Watch
  fortsatt kan ha målt trening offline.
- Tester dekker lang frakobling, gjenopptakelse og overtid.
  Fysisk enhets- og HealthKit-verifisering gjenstår.

### Fase 4 – Watch-originert styrkeoppstart under konflikt

- En standalone Watch-bootstrap tar nå hensyn til både aktive
  styrke-/løpeopptak og den reserverte asynkrone oppstarten for
  løp, gåing og styrke. Watch-meldinger går dermed gjennom samme
  opptaksgrense som appens ordinære Quick Train-/planlagte start.
- `StrengthWorkoutStore.startFromWatchSnapshot` avviser aktiv
  styrke, signert-ut konto, ferdig lagret økt og opptatt slot.
  Den opprinnelige økt-ID-en fra Watch beholdes ved en godkjent restore.
- `requestSnapshot` for en annen pågående økt blir ikke konsumert
  og kan ikke erstatte en eksisterende registrering. Bootstrap for
  en allerede lagret økt blir anerkjent som håndtert uten å
  reaktivere eller duplisere historikk.
- Tester dekker eksisterende styrkeøkt, fullført økt, opptatt
  opptaksslot og tillatt bootstrap. Fysisk reconnect etter
  bortfall og kryssaktivitetstest på Watch gjenstår.

### Fase 4 – kontoavgrensning for Watch-styrkekommandoer og iPad-status

- Watch-observatøren behandler ikke gjenoppretting, settkommandoer,
  pulsoppsummering eller køkvitteringer før den eksisterende
  `StrengthWorkoutStore` har lastet **samme** konto som er innlogget.
- En forsinket privat styrkestatus for iPad publiseres ikke med
  øktdata fra forrige konto under kontobytte. Utgående Watch-snapshot
  er underlagt samme konto-kontroll.
- Ny test verifiserer at en styrkehistorikk først er konto-klar
  etter en faktisk `switchAccount`; utlogging og fremmed konto
  blokkerer Watch-data. Ingen ny konto-/opptakslagring innføres.

### Fase 4 – flere Watch-økter i samme kontos frakoblingskø

- Watch-journalen binder nå alle muterende settkommandoer til **både**
  riktig konto og riktig aktiv økt-ID. Tidligere kunne en annen
  økt på samme konto bli brukt som grunnlag for å konsumere en
  forsinket kommando uten å registrere settet; det er nå avvist.
- Kommandoer fra en annen Watch-økt blir liggende i eksisterende
  durable kø for senere gjenoppretting. Ny Watch-bootstrap kan
  fortsatt tas imot uten aktiv styrke, mens en leseforespørsel
  fra eldre Watch-build beholder kompatibilitet.
- Observeren avviser ID-konflikter uten falsk kvittering selv om
  en feilaktig kommando når helt frem til behandlingsleddet.
  Tester dekker to økter på samme konto og Watch-bootstrap.

### Fase 4 – varig Watch-journal: avsluttede økter og riktig hendelsesrekkefølge

- Forsinkede kommandoer fra en økt som allerede er **varig lagret**
  i den innloggede kontoens `strengthHistory` får nå kvittering uten
  å mutere sett eller gjenskape HealthKit-opptak. Uten samme ferdige
  økt-ID blir de liggende til korrekt gjenoppretting.
- Watch-initiert bootstrap prioriteres før settkommandoer, også om
  WatchConnectivity sendte en senere oppstartspakke enn sine
  settpakker. Etter bootstrap brukes opprinnelig `sentAt` og
  UUID som deterministisk sortering, ikke tilfeldig ankomstrekkefølge.
- Tester dekker feil eier, ukjent/ferdig økt, eldre Watch-format
  uten konto-ID og setthendelser som ankommer før bootstrap.
  XCTest som bruker aktørbundet `StrengthWorkoutStore` er også merket
  `@MainActor`.

### Fase 7 – Watch-resultat: avslutt bare korrekt økt, aldri neste treningslogg

- `WatchWorkoutResult.id` opprettes når Watch lagrer resultatet.
  Den er **ikke** identiteten til styrketreningsøkten. Ny
  `ATHLTHWatchStrengthResultIdentityPolicy` bruker den stabile
  `strengthSnapshot.workoutID` mot eksisterende `StrengthWorkoutLog.id`.
  Bare eldre Watch-resultater uten snapshot får en streng,
  tidsbegrenset fallback for telefon-initiert Watch-opptak.
- En gammel Watch-ferdigstilling kan nå verken avslutte feil
  aktiv styrkeøkt eller feste kalorier/puls til en ny økt.
  Metrics for allerede lagrede økter oppdateres på **eksakt
  historikk-ID**, med separat kontosjekk og atomisk historikk-skriving.
  Den siste fullføringsjournalen erstattes ikke med en eldre økt.
- Når Watch eier HealthKit er `result.endedAt` også autoritativ
  sluttid i styrkehistorikken, ikke klokken når iPhone senere
  mottar resultatet. Ved diskfeil beholdes Watch-resultatet i
  eksisterende kø slik at en retry ikke lager dobbelt resultat.
- Regresjonstester dekker avvikende økt-ID, ny aktiv økt,
  HealthKit-backfill på eldre fullført økt og faktisk sluttid.
