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
