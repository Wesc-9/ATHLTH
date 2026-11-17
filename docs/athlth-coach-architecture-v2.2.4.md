# ATHLTH Coach – samlet progresjons- og treningsintelligens

**Utgangspunkt:** iOS-/Watch-release `release/v2.2.4`.  
**Sporing:** [hovedsak #49](https://github.com/Wesc-9/ATHLTH/issues/49); [fase 1 #50](https://github.com/Wesc-9/ATHLTH/issues/50), [fase 2 #51](https://github.com/Wesc-9/ATHLTH/issues/51), [fase 3 #52](https://github.com/Wesc-9/ATHLTH/issues/52), [fase 4 #53](https://github.com/Wesc-9/ATHLTH/issues/53), [fase 5 #54](https://github.com/Wesc-9/ATHLTH/issues/54).

## Beslutning
ATHLTH Coach er **den eneste brukervendte coachen**. Vi skal ikke introdusere «Lift IQ» som eget produktnavn, skjerm eller uavhengig AI-system. Treningstilpasning er et produktlag over deterministiske domeneprosessorer: styrke, løping, plan, restitusjon. En eventuell språkmodell **forklarer** beslutninger, den skaper aldri på egen hånd uverifiserte belastninger.

**Sikkerhetsinvariant:** analyse og forslag er skrivebeskyttet. En fremtidig, fullført treningsøkt endres aldri. Endringer i plan eller aktive sett krever eksplisitt brukerhandling.

## Kartlagt eksisterende kode (fase 1)
- `ATHLTH/Planning/ATHLTHCoachStrengthIntelligence.swift` – 56-dagers styrkehåndtert økt- og settanalyse, RPE-/volumsignaler, forslag med «review_small_increase» og «review_plateau».
- `ATHLTH/Strength/StrengthWorkoutStore.swift` – live styrke, fullførte loggsett og separat `progressionSuggestion` via `AthleteStrengthProgression` (tidligere matchet etter navn alene).
- `ATHLTH/Planning/ATHLTHTrainProgressionCoach.swift` – konservative planforslag med to separate dokumentert vellykkede, planlinkede økter; forslag endrer ikke plan direkte.
- `ATHLTH/Planning/TrainingBlockProgressionEngine.swift` – preview for trinnvis belastning/repetisjoner/restitusjon i fremtidige økter. Må ikke konkurrere med individuell styrkeprogresjon.
- `ATHLTH/Planning/ATHLTHCoachRunningIntelligence.swift` og `ATHLTHCoachTrainingContext.swift` – egne leseavgrensede analyser.
- `ATHLTH/Strength/StrengthWorkoutModels.swift` – completed reps, weight, RPE/RIR, settype, oppvarming, innsatssegmenter, avanserte gruppetyper, motstandstrinn, måling og restitutionspauser.

### Oppdaget risiko og avgrensning
- Historikkens `ExerciseSnapshot` lagrer navn og utstyr, **ikke** den kanoniske bibliotek-ID-en. `StrengthExerciseLog.plannedExerciseID` er knyttet til planlagt øvelse, ikke nødvendigvis global biblioteksidentitet. Dette skal **ikke** gjettes til samme ID.
- Navn alene kan forveksle apparattyper og vektskala. Den første nye datagrensen krever likt normalisert navn, utstyr og ikke-konfliktende primærmuskel, men *kan ennå ikke* garantere identisk spesifikt apparat/lastenhet; fase 2–3 må innføre eksplisitt proveniens.
- Eksisterende live-, plan- og coach-forslagsmotorer har ulike terskler og tidshorisonter. De er ikke konsolidert i én anbefalings-API ennå: dette skal gjøres før fase 1 kan lukkes.
- Nettverk og generativ modell skal ikke få private rå treningslogger uten gjeldende tillatelse.
- Ingen av disse punktene begrunner automatisk planendring, eller å anta at fremtidig funksjonalitet er ferdig.

## Første leveranse i arbeidsgren (ikke merged)
- `ATHLTHCoachStrengthComparableHistory` er en ny skrivebeskyttet datagrense for *sammenlignbare* fullførte historiske sett. Den gir kilden og tidsvinduet uten å beregne en personlig anbefaling.
- Live `StrengthWorkoutStore.progressionSuggestion` leser fra denne i stedet for å velge navnelike øvelser på egen hånd. Den eldre progresjonsalgoritmen brukes fortsatt; videre arbeid ligger i fase 2.
- Nye enhetstester dekker forveksling av benkpress-varianter, utstyr, oppvarming, skip, tidsmål, motstandsnivå og ferske/eldre økter.
- Testene er lagt til i Swift-testtarget men **må kjøres i faktisk iOS/Xcode-bygg**. Ikke rapporter dem som grønne før pipeline/simulator har bekreftet det.

## Planlagte beslutningskontrakter
En framtidig `CoachRecommendation` bør inneholde:
1. **Omfang:** exercise library ID hvis proven, apparat-/load-kind og mål (styrke/hypertrofi/utholdenhet).
2. **Bevis:** distinkte workout ID-er og arbeidssett-ID-er, ferdigtidspunkt, mål vs oppnådd, enhetsdefinisjon.
3. **Forslag:** `hold`, `increaseReps`, `increaseLoad`, `reduceLoad`, `reviewVolume`, `insufficientEvidence`.
4. **Årsak:** konkret dokumentert regel, datakvalitets-/tillitsnivå, hvorfor alternativ ikke ble valgt.
5. **Handling:** kun `preview`; bruker må godta/beholde/justere før synkronisert mutasjon.

## Faser og ferdigkriterium
- [ ] Fase 1 – grunnlagskartlegging, identitet, felles API og compile/verifikasjon (**pågår**).
- [ ] Fase 2 – algoritmisk styrkeprogresjon med sikkerhetstester.
- [ ] Fase 3 – integrert UI i Basic/Advanced, live, plan, iPad og Watch.
- [ ] Fase 4 – innsikt og godkjente planjusteringer via Coach.
- [ ] Fase 5 – komplett test, ytelse og TestFlight.

**Oppdater dette dokumentet og #49 ved hver ferdigkontrollerte fase.** Ikke marker noen av fasene complete før sjekklistene og CI-/QA-bevis er klare.
