# ATHLTH Coach – samlet progresjons- og treningsintelligens

**Arbeidsgren:** `release/v2.2.4` (alle endringer implementeres direkte på gjeldende release-gren).  
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
- Eldre historikk i `ExerciseSnapshot` lagrer navn og utstyr, men ikke den kanoniske bibliotek-ID-en. Nytt `Exercise.snapshot` lagrer nå valgfri `libraryExerciseID` for fremtidige økter (uten å kreve migrering av eldre data). `StrengthExerciseLog.plannedExerciseID` er knyttet til planlagt øvelse, ikke nødvendigvis global biblioteksidentitet. Dette skal **ikke** gjettes til samme ID.
- Navn alene kan forveksle apparattyper og vektskala. Den første nye datagrensen krever likt normalisert navn, utstyr og ikke-konfliktende primærmuskel, men *kan ennå ikke* garantere identisk spesifikt apparat/lastenhet; fase 2–3 må innføre eksplisitt proveniens.
- Live- og planlagt styrke bruker nå samme evidence-policy og `ATHLTHCoachStrengthDecision` for vurdering av en eventuell økning. Andre Coach-/periodiseringssignaler er ennå ikke samlet, og endelig beslutnings-API mangler målbasert repetisjons-/volumstyring.
- Nettverk og generativ modell skal ikke få private rå treningslogger uten gjeldende tillatelse.
- Ingen av disse punktene begrunner automatisk planendring, eller å anta at fremtidig funksjonalitet er ferdig.

## Første leveranse direkte i release/v2.2.4
- `ATHLTHCoachStrengthComparableHistory` er skrivebeskyttet datagrense for *sammenlignbare* fullførte historiske sett, med kanonisk-ID når registrert, konservativ navne-/utstyrsfallback og kontroll av hoppede/ugyldige sett. Gir også felles `TargetEvidence` for å avgjøre om planlagte arbeidssett faktisk ble gjennomført.
- Nytt `ATHLTHCoachStrengthDecision` samler vurdering av to separate vellykkede økter, siste mislykkede økt som veto, tillitsnivå og krav om manuell godkjenning. Live `StrengthWorkoutStore.progressionSuggestion` og planforslag via `ATHLTHTrainProgressionCoach` bruker beslutningsregelen. Den eldre `AthleteStrengthProgression` beregner fortsatt det endelige live-forslaget; senere steg samordner all dosering.
- Nye enhetstester dekker øvelsesidentitet, ulikt utstyr, oppvarming, skip, tidsmål, motstandsnivå, ferske/eldre økter, RIR, urealistiske økninger, første økt og nylig mislykkede sett. Live viser nå `ATHLTH Coach` som avsender for progresjonsforslaget.
- Testene er lagt til i Swift-testtarget men **må kjøres i faktisk iOS/Xcode-bygg**. Ikke rapporter dem som grønne før pipeline/simulator har bekreftet det.
- Første kodegrunnlag ble merget til release i [PR #55](https://github.com/Wesc-9/ATHLTH/pull/55), merge-commit `094e9759`. Videre Coach-arbeid gjøres direkte på `release/v2.2.4`, uten separat feature-gren, i tråd med brukerens instruks.

## Etablert delkontrakt og neste utvidelser
`ATHLTHCoachStrengthDecision.Assessment` inneholder allerede `action`, `reason`, `confidence`, `sourceWorkoutIDs`, `sourceSetIDs`, `proposedWeightKg` og `requiresUserApproval`. En fullstendig framtidig `CoachRecommendation` må i tillegg inneholde:
1. **Omfang:** exercise library ID hvis proven, apparat-/load-kind og mål (styrke/hypertrofi/utholdenhet).
2. **Bevis:** distinkte workout ID-er og arbeidssett-ID-er, ferdigtidspunkt, mål vs oppnådd, enhetsdefinisjon.
3. **Forslag:** `hold`, `increaseReps`, `increaseLoad`, `reduceLoad`, `reviewVolume`, `insufficientEvidence`.
4. **Årsak:** konkret dokumentert regel, datakvalitets-/tillitsnivå, hvorfor alternativ ikke ble valgt.
5. **Handling:** kun `preview`; bruker må godta/beholde/justere før synkronisert mutasjon.

## Iterasjon 2 – forslag om repetisjoner og volum (direkte på release)
- `ATHLTHCoachStrengthRepetitionVolume` er en deterministisk, skrivebeskyttet regelmotor. Den krever eksplisitt repetisjonsområde og et faktisk lagret planmål (`getStronger` eller `buildMuscle`). Ingen oppdiktede intervaller eller anbefalinger fra bare én god økt.
- Økningsforslag: kun én repetisjon av gangen ved to distinkte planlinkede og fullførte økter, med registrert innsats (RIR/RPE) og korrekt arbeidsvekt. Manglende/høy innsats, hoppede sett, ukjent vektenhet eller mismatchet øvelse skal blokkere økning.
- I `ATHLTHTrainProgressionCoachView` aktiverer brukeren selv repetisjonsforslag og velger min/maks. Når vekt og reps begge kunne økes, prioriteres reps innen valgt område (dobbel progresjon).
- `AppSessionStore.applySuggestedTrainingRepetitions` kontrollerer planversjonen og **beregner forslaget på nytt** ved eksplisitt godkjenning, oppdaterer kun arbeidsrepetisjonene for én fremtidig planlagt øvelse, og bevarer oppvarming, sett-ID-er og fullførte økter.
- For muskelvekst kan tre sammenlignbare økter ved øvre repetisjonsgrense over minst 14 dager gi `reviewTrainingVolume`. Coach viser nå et eget **informasjonskort for treningsmengde** med antall relevante økter og sett; dette er verken en diagnose eller automatisk økning i sett. Målbasert volumdosering gjenstår.
- `ATHLTHCoachStrengthIntelligence` bruker nå samme historikk-/vektbeslutning og skiller utstyrsvarianter for å unngå motstridende Coach-signaler.
- Nye tester: `ATHLTHCoachStrengthRepetitionVolumeTests`, utvidet `ATHLTHTrainProgressionCoachTests`, `ATHLTHCoachStrengthIntelligenceTests`.
- Sikkerhetsregler: **fullstendig hoppet over siste økt får ikke forsvinne fra sammenligningen** og eldre gode økter skal da ikke gi økningsforslag. Gjentatt samme øvelse i én økt er tvetydig og kan ikke telle som uavhengige vellykkede økter. Planlagt vektprogresjon grupperes etter kanonisk øvelses-ID der den finnes (navneendring bevares), ellers konservativt navn/utstyr.
- Ved vektjustering krever Coach nå **eksplisitt bekreftelse per øvelse** på at historisk vektangivelse (f.eks. per manual / totalt) samsvarer og at valgt økning er tilgjengelig med utstyret. Bytte av økningssteg nullstiller bekreftelsen. Dette løser ikke behovet for framtidig strukturert belastningsproveniens i alle Watch-/treningslogger.
- Volumkort og fremtidige repetisjonsforslag bruker samme datagrunnlag (`progressionReviews`). Ingen endring i ferdige økter eller antall sett.

- Gjenstående: Xcode-/iPhone-/iPad- og Watch-verifikasjon, full UI-testing, utstyrsproveniens (total kg versus per manual, konkrete apparat), fremtidige volumforslag, restitusjonskontekst, end-to-end-synkronisering og kjørt testbevis. Ingen av de fem fasene er merket ferdig.

## Faser og ferdigkriterium
- [ ] Fase 1 – grunnlagskartlegging, identitet, felles API og compile/verifikasjon (**pågår**).
- [ ] Fase 2 – algoritmisk styrkeprogresjon med sikkerhetstester (**påbegynt: godkjente vekt- og repsforslag, volum kun review; sett-/utstyrsdosering og verifikasjon gjenstår**).
- [ ] Fase 3 – integrert UI i Basic/Advanced, live, plan, iPad og Watch (**kun avsendernavn i eksisterende livekort oppdatert**).
- [ ] Fase 4 – innsikt og godkjente planjusteringer via Coach.
- [ ] Fase 5 – komplett test, ytelse og TestFlight.

**Merk:** Syntaks-/bygg- og teststatus må verifiseres i GitHub Actions før noen fase lukkes. `release/v2.2.4` er riktig kodegren. Oppdater dette dokumentet og #49 ved hver ferdigkontrollerte fase. Ikke marker noen av fasene complete før sjekklistene og CI-/QA-bevis er klare.
