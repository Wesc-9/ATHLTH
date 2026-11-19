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
