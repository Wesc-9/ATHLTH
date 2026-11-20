## 2.2.6 – iPad viser original aktiv styrkeklokke og faktisk Watch-hybridfase

- Den private, allerede samtykkestyrte iPad-spektatoren har sluttet å beregne styrkevarighet fra rå veggklokke. Den bruker original styrkejournal sin aktive sesjonstid (med pause/offline-regnskap); ingen ny timer, journal eller HealthKit-session.
- Når styrkeopptaket eies av Watch og den samme opprinnelige HealthKit-økten er bekreftet med korrekt konto, UUID, start og ferskt livesnapshot, kan iPad vise aktuell løp/styrke/pause-fase og Watch sin aktive tid. Ved gammel/feil konto, ugyldig UUID eller forsinket Watch-telemetri beholdes journalens trygge lokale visning.
- Kilden deles fortsatt bare gjennom eksisterende eksplisitt iPad-samtykke. Ukjente sensorverdier for styrke/hybrid fylles ikke inn fra planmål. Tester dekker pausetid, frakobling, hybridfase, kontobytte og ugyldig Watch-UUID.
- Fysisk treenhetstest og grønn samme-commit CI kreves fortsatt.

## 2.2.6 – riktig aktiv deløkt for Watch-hybrid og velvære

- Watch styrke/hybrid publiserer to valgfrie, bakoverkompatible presentasjonsflagg fra original styrkejournal: aktiv løpedel og aktiv hvile. Den felles live-projeksjonen bruker nå aktiv sport (løp / pause / styrke), mens ÉN opprinnelig Watch HealthKit-økt, UUID, planlenke og eier beholdes.
- Alle øvrige native Watch-sporter går gjennom én felles sportskontrakt, og en irrelevant styrkehybrid-markør kan ikke omklassifisere en annen sportsøkt.
- Strukturerte yoga- og meditasjonsblokker beholder nå egen aktivitet i livevisningen i stedet for å bli slått sammen til bare «bevegelighet», mens det felles wellness-planfilteret er uendret.
- Nye regresjoner dekker fasebytter, pause, original øktidentitet, andre Watch-sporter, yoga og meditasjon. Dette oppretter ingen ny writer, sportstype i HealthKit eller historikk. Same-commit CI og fysisk enhetsverifikasjon gjenstår.

## 2.2.6 – måleproveniens og frakoblet Watch uten falsk økt

- Manuell Custom Quick-historikk bruker samme distansekapabilitet som aktiviteten faktisk har i skjermbildet. Stale/eksterne data kan ikke lagre fiktive kilometer for yoga, HIIT, sirkel og bevegelighet; eksisterende historie slettes eller migreres ikke. Manuell distanse for støttede aktiviteter er fortsatt uttrykkelig uverifisert.
- En Watch-styrkejournal skal kunne leve videre under kort forbindelsesbrudd. Kontoeier verifiseres fortsatt ved aktivt speil, men en gammel Watch-sensorprøve brukes ikke som krav for å lese den originale styrkejournalen. Bare fersk, identitetsverifisert Watch-telemetri kan publiseres som Watch-live.
- Regresjonstester dekker alle manuelle sportsvalg, misvisende distanser og utdatert Watch-sensormåling. Same-commit CI og fysisk test gjenstår.

## 2.2.6 – planbundet Watch-live uten tapt originalidentitet

- Watch inkluderer nå `plannedCalendarSessionID` i det opprinnelige live-snapshotet, i tillegg til allerede lagret Watch-gjenoppretting og resultat. Universell aktiv Watch-projeksjon viser original planlagt session-ID for alle støttede Watch-aktiviteter; fri trening og legacy Watch-overføringer forblir uten plan-ID.
- Ved aktivt Watch-speil kontrolleres original konto og gyldig snapshot også hvis et matchende styrkecheckpoint allerede finnes på iPhone. Fremmed/gammel melding kan ikke autorisere et livespeil.
- Nye XCTest dekker alle native Watch-idretter, pause, fri økt, legacy Codable og kontobytte. Ingen ny HealthKit-sesjon, opptaker eller treningshistorikk.
- Samme-commit iPhone/iPad/watchOS-build, XCTest og fysiske HealthKit/samtykke-prøver kreves før releasegodkjenning.

## 2.2.6 – planlenken overlever Apple Watch-appomstart

- Eksisterende Watch HealthKit-gjenopprettingscheckpoint har nå `plannedCalendarSessionID` som et valgfritt, bakoverkompatibelt felt, i tillegg til original ATHLTH-ID, eier, fjernstart-ID, rute og tidslinje. Ved ny appstart tas kalenderkoblingen med videre til originalt resultat og planoppfølging.
- Verifisering av original Watch-aktivitet og faktisk HealthKit-start (±5 sek) gjøres nå FØR noe av eldre checkpoint-eier, remote-ID, rute, Audio Coach, intervalldata eller styrkefremdrift kan reetableres. Et gammelt checkpoint kan ikke knyttes til en annen HKWorkoutSession med samme sport.
- Ukjent/eldre snapshot uten dokumentert original start skal ikke tilordnes en vilkårlig økt. Den faktiske gjenopprettede HealthKit-sesjonen vises fortsatt, men uten ubekreftede plan-/kontodata.
- Regresjonstester dekker alle Watch-treningsformer, samtidighet, feil sport og manglende/avvikende starttid. Native samme-commit build og fysisk HealthKit-recovery gjenstår.

## 2.2.6 – opprinnelse ved planbundet Watch-start

- Klargjort økt brukt av automatisk `HKHealthStore.startWatchApp` merkes nå som telefoninitiert, mens en START-knapp som faktisk trykkes på Apple Watch fortsatt er Watch-initiert. Begge bruker samme originale HKWorkoutSession; dette oppretter ingen ekstra HealthKit-opptak.
- Skillet er viktig: tidligere kalte både de to rutene `startPreparedWorkout`, som alltid satte `workoutInitiatedLocallyOnWatch=true`. Dermed kunne `activeRelayRequestID` nullstilles i den private Watch-starteren, selv om iPad-fjernstart hadde en bekreftet `clientRequestID`. Nå bevares staged remote-korrelasjon for automatisk planlagt løp og gå.
- WatchHome/Watch-knapp benytter uendret standardparameter (lokal start), mens WatchApp automatisk start eksplisitt setter telefoninitiert. Nye regresjonstester dekker opprinnelsesvalget. Samme-commit iOS/WatchOS-build og faktisk relay-test gjenstår.

## 2.2.6 – Watch-resultater kun én gang fra korrekt HealthKit-opptak

- Ved sluttføring kreves både original start, matching HealthKit `startDate` (±5 sek), faktisk avslutning, aktiv finish-prosess og ingen tidligere publisert kvittering. Et sent GPS-rute-/HealthKit-callback fra en gammel økt kan derfor ikke fullføre eller overskrive en nyere aktivitet.
- En korrupt, ufullstendig, planbundet prepared-overføring stopper på Watch i stedet for å bli startet som en vanlig fri løpe-/gåøkt etter timeout. En normal legacy/fri overføring forblir kompatibel.
- Deduplisering på iPhone etter kilde-HealthKit UUID brukes fortsatt som før; dette er i tillegg en sender-side sperre, ikke en ny historikk.
- Tester dekker dobbelpublisering, manglende original start, forsinket gammel callback, ugyldig sluttid og starttids-jitter. Fysisk HealthKit-oppførsel og siste commit må bekreftes med CI.

## 2.2.6 – én planbundet Watch-handoff for løp OG gå

- `WatchPreparedWorkoutTransfer` får to valgfrie, bakoverkompatible felter for original plan og økt. Ved planbundet iPhone-/iPad-oppstart settes begge, og Watch binder faktisk `plannedCalendarSessionID` til den autoritative HKWorkoutSession uten å opprette en ny opptaker.
- Planlagt gåing bruker nå den eksisterende, komplette forberedte Watch-overføringen, slik løping allerede gjorde. Watch-appens automatiske start venter på matching aktivitet/innendørsstatus, og rute-/intervalldata settes før oppstart.
- Watch kan ikke bruke en forberedt økt med ufullstendig planidentitet, en gjenopprettet eller fortsatt eksisterende HealthKit-sesjon. En forberedt økt kvitteres først som forbrukt når Watch faktisk er i `running` eller `paused`, ikke i `idle`, `failed` eller `completed`.
- Den eksisterende eldre oppstarten brukes fortsatt dersom en prepared-melding ikke har nådd klokken innen den dokumenterte kompatibilitetsfristen. Denne forsinkelsestilstanden trenger fortsatt fysisk iPhone/Watch-reproduksjon før planmarkering kan garanteres 100 %.
- XCTest dekker plan/session roundtrip for løp og gå og avviser halvkoblede overføringer. Native build/HealthKit/TestFlight er ikke verifisert.

## 2.2.6 – Watch start, reset og feil ved HealthKit-sluttlagring

- Watch lokalt/forberedt og HealthKit-initiert start bruker én policy som blokkerer nye økter mens original `HKWorkoutSession` finnes eller `recoverActiveWorkoutSession()` venter. Dobbelstart kan ikke tømme gammel eier, rute eller Audio Coach før preflight.
- `reset()` kan ikke nullstille en faktisk aktiv/stoppet/ended, men ennå ikke korrekt fullført HealthKit-økt; en vellykket fullført økt kan fortsatt lukkes. `end()` krever en eksisterende session før status endres til avslutning.
- Ved HealthKit-finish/collection-feil beholdes original gjenopprettings-ID/checkpoint hvis den originale sessionen faktisk var startet. Før en reell sesjon oppstår, fjernes mislykket oppstart som før. Ingen separat recorder/historikk og ingen falsk fullføringskvittering.
- Nye stateløse tester dekker alle Watch-aktiviteter, recovery, Reset og save-failure. Native same-commit Watch-bygg og fysisk recovery må fortsatt verifiseres.

## 2.2.6 – ingen oppdiktet ro-distanse fra Apple Watch / Audio Coach

- Apple Watch og iPhone-speilets rutine- og custom Audio Coach bruker nå den **opprinnelige HealthKit-kildens** distansekapabilitet i tillegg til generisk sportkategori. Watch registrerer ikke verifisert ro-distanse med dagens konfigurasjon; derfor skal en roøkt ikke lese opp «distanse 0» på en tidsstyrt varsling eller forsøke å behandle programmert distanse som sensoravlesning.
- Løp, gå og faktisk målt sykkeldistanse beholder distansevarsler. Brukerens lagrede coach-regler endres ikke; bare aktive, ikke-verifiserbare metrikker utelates fra opplesning. Ved en fremtidig dokumentert ro-sensoradapter kan distansekapabiliteten aktiveres i samme motor.
- Regresjonstest dekker rene tidstriggere, distansetriggere, tid+distanseregler og sykling med/uten gyldig distansekilde. Samme-commit CI og fysiske Watch-lydtester gjenstår.

## 2.2.6 – opprinnelig plan er alltid fasit ved løpeopptak

- Den samme planen som er validert mot `plannedPlanID/plannedSessionID` prioriteres nå som kilden til både 1) treningsintervaller som lastes til Watch/iPhone, 2) validering før opptaksstart og 3) eventuell planlagt rute. Dermed kan et gammelt Quick Run-utkast eller en mottatt kopi med annet routeID/drag ikke overstyre treningsplanen mens den bokføres som original.
- Vanlige frie Quick Run-konfigurasjoner bruker fremdeles sitt eget Advanced-utkast. Et bevisst manuelt rutevalg (`configuration.route`) har fortsatt forrang over planruten. Ingen endring i workout UUID, HealthKit-writer eller opptakslagring.
- XCTest dekker gammel plan-kopi med motsigende intervaller og rute, samt fortsatt støtte for Quick Run uten plan. Native compile/test på samme commit og fysisk enhetsverifikasjon gjenstår.

## 2.2.6 – originale opptakslogger styrer den felles opptaksplassen

- Alle nye iPhone/Watch-preflight-sperrer kontrollerer både de opprinnelige `PhoneWorkout`- og `StrengthWorkoutLog`-objektene og de avledede universelle sesjonsprojeksjonene. Dersom en eksisterende journal er lastet inn, men en Live/HealthKit-projeksjon mangler et øyeblikk under gjenoppretting, skal en ny treningsform IKKE kunne overta det opptaket.
- Oppdatert `reserveLaunch`, `mayStartRunning`, `mayStartStrength`, `mayBootstrapWatchStrength` og `requireAvailableRecordingSlot`; ingen ekstra HealthKit-writer eller separat treningshistorikk.
- Regresjonstester dekker opptatt original styrkejournal ved samtidig løpe-/styrkeoppstart og ren policy for originale kilder. Native samme-commit CI og fysisk verifikasjon gjenstår.

## 2.2.6 – Apple Watch: ingen nullstilling av pågående økt ved dobbel start

- Både vanlig og forhåndslastet lokal Watch-start sjekker nå én felles startsperre FØR de nullstiller lydcoach, rute, styrkekø, eierskap eller treningsplan. Sperren gjentas etter et asynkront svar fra iPhone; dermed kan ikke et sent dobbelttrykk korrupttere et allerede aktivt originalt HKWorkoutSession.
- Samme regel gjelder løp, gå, styrke, sykling, roing, HIIT, funksjonell trening, trappetrening, yoga og øvrige Watch-aktiviteter. Original HealthKit-sesjon, én workout UUID og avslutningsdelegaten berøres ikke.
- Stateløs policy har regresjonstest for samtlige Watch-aktiviteter og alle opptatte oppstartstilstander. Full WatchOS-bygg og fysisk test kreves fortsatt.

## 2.2.6 – én ekte opptakssperre ved fjernstart, ikke egne UI-varianter

- Mottak av iPad-fjernstart bruker nå `ATHLTHUniversalWorkoutAdmission.isOccupied` i stedet for ad hoc-sjekker av bare PhoneWorkout, StrengthWorkout og WatchMirror. En gjenopprettet strukturert økt, aktiv manuell tidtaker, iPhone pending launch og Watch-start før speiling blokkerer samme nye opptaksplass før eventuelle relay-sideeffekter.
- Valideringen av komplett plan-ID og session-ID skjer også på iPad **før** fjernkommandoen sendes til serveren, og på iPhone ved mottak. Den tidligere eksisterende reservasjonen i opptakskoordinatoren forblir siste autoritative sperre når asynkrone HealthKit-kall foretas.
- Ingen ny HealthKit-eier, workouthistorikk eller automatisk iPad-samtykke. Samme-commit CI og fysisk test gjenstår.

## 2.2.6 – ende-til-ende bevaring av plan-ID ved iPad-fjernstart

- Original `plannedPlanID` og `plannedSessionID` følger nå de eksisterende versjon-1-relémeldingene for Quick Run og Quick Walk. Mottaker-iPhone krever begge eller ingen, og sender dem videre til original `WorkoutLaunchCoordinator`, som kontrollerer sport og faktisk eksisterende plan før opptak.
- For en planbundet fjernstart vil en eldre/kopiert inviteringsplan ikke erstatte den kanoniske treningsplanens deløkter; original plan på telefon er fasit. Manglende original plan betyr avvisning, aldri fri økt.
- Vanlig Free Run/Walk og den eksisterende dedikerte styrkeflyten fungerer uten nye obligatoriske felt. Strukturerte blandingsopptak konverteres ikke til løping; ingen ekstra HealthKit-opptaker, sykkel-PR eller dupliserte historikkobjekter.
- Tester validerer hele planlenken og avslår delvis og uautorisert oppstart. Full samme-commit build, Watch/iPad testing og faktisk HealthKit-verifikasjon gjenstår.

## 2.2.6 – effektiv og sikker iPad-rekonstruksjon

- Når original strukturert livevisning fortsatt er åpen, benyttes siste bekreftede interne UI-status. Bare ved faktisk prosess-/scene-gjenoppretting dekodes original, kontotilhørende checkpoint fra disk. Slik unngår vi å dekode store intervallplaner hvert fjerde sekund ved vanlig iPhone-bruk.
- Manglende stegindeks eller ugyldig pauseregnskap gir ingen rekonstruert liveøkt. Norsk/engelsk fallback testes språk-uavhengig. Originalt samtykke, trenings-ID og kildeeiere beholdes.

## 2.2.6 – iPad kan hente tilbake den faktiske strukturerte økten

- Den originale strukturerte iPhone-checkpointen lagrer nå valgfri `sourceTitle`, og iPad-spektatorens eksisterende iPhone-publisher kan gjenoppbygge read-only livevisning fra den verifiserte, kontotilhørende checkpointen etter prosessomstart. Samme trenings-ID, aktiv deløkt, tid, pause og stegposisjon beholdes. Historikk og motor opprettes ikke på nytt.
- `ATHLTHStructuredSpectatorSnapshot` deler én manuell kildekontrakt for normal livebruk og gjenopprettet status. Verken planlagt distanse, puls, GPS, fart eller kalorier presenteres som sensorverdier.
- iPad får IKKE automatisk tilgang: opprinnelig iPhone-eiers godkjenning for akkurat denne økten gjelder fortsatt, og etter appstart må samtykket bekreftes på nytt. Utgått eller korrupt checkpoint gir ingen speilet treningsstatus.
- XCTest dekker rekonstruert hybridøkt, original plan/tittel og pause uten fiktive sensormålinger. Samme-commit CI og ekte iPhone/iPad-verifikasjon gjenstår.

## 2.2.6 – bevar opprinnelig planlenke i den faktiske strukturerte økten

- Det eksisterende strukturerte iPhone-sjekkpunktet lagrer nå en valgfri `sourcePlanID` sammen med original workout-ID, aktivt steg, klokke og fullføringskvittering. Gamle sjekkpunkter uten feltet kan fortsatt dekodes og gjenopprettes.
- En gjenopprettet økt beholder original planlenke selv om den åpnes fra en annen inngang som ikke har plan-ID; en eksplisitt, motsigende plan-ID avvises før sjekkpunktet kan overskrives. Lagring av fullføring bruker den restaurerte planlenken, ikke en tilfeldig ny SwiftUI-inngang.
- Den universelle, skrivebeskyttede aktivtilstanden eksponerer riktig planlagt session-ID når den opprinnelige strukturerte økten er planbundet. Identiteten til den originale journalen og opptakseieren endres aldri. Regresjonstester dekker planlenke, gjenoppretting og motstridende plan-ID.
- Ingen ny HealthKit-writer eller egen historikk er lagt til. Same-commit build, XCTest og fysiske enhetstester gjenstår.

## 2.2.6 – korrekt aktiv treningsform og idempotent gjenoppretting

- Den ene universelle strukturerte tilstanden rapporterer nå sport for AKTIV deløkt, ikke overordnet "hybrid". Løp → sykling → pause → styrke beholder samme recording owner, stable workout UUID og klokke mens aktivitet, livekontroll og fase endres. Den eksisterende private iPad-spektatoren bruker også aktiv deløkt ved publikasjon; ingen ekstra HealthKit-opptaker eller ny øktidentitet introduseres.
- Strukturert fullføringshistorikk avviser et nytt kvitterings-ID for nøyaktig samme source-workout og originale starttid etter krasj/retry. En ny start av samme *ulenkede* treningsøkt er fortsatt et nytt, gyldig treningsforsøk. Eldre låsing av gjennomførte planlagte økter beholdes.
- Nye XCTest dekker sportsoverganger på samme økt og idempotent history-save ved gjenoppretting. Full same-commit bygg, iPhone/iPad/Watch og HealthKit-opptaksverifisering gjenstår.

## 2.2.6 – ikke mist plan-ID ved gjenopptak eller Quick Train

- Før Quick Run og Quick Walk starter et planlagt opptak, kontrollerer `ATHLTHPlannedLaunchIdentityPolicy` at både plan-ID og session-ID finnes sammen. Et mangelfullt/halvt koblet planobjekt blir avvist i stedet for å bli startet som en «fri» økt hvor planens faser eller identitet kan forsvinne.
- Vanlig fri Quick Train uten planlenke fungerer fortsatt. Hele planlenken og eksisterende opptakseier beholdes; ingen ekstra HealthKit-opptaker eller øktjournal er introdusert.
- Ny XCTest dekker alle kombinasjoner av manglende og fullstendige lenker, og tidligere rutevalidering gjelder fortsatt.

## 2.2.6 – enhetlig opptaksplass også ved Watch-start uten speil

- `ATHLTHWorkoutSessionFoundation.requireAvailableRecordingSlot` bruker nå én testbar regel for pending iPhone, manuell og strukturert tidtaker, aktive Watch-speil og Watch-opptak som er startet før speilet kommer. Det hindrer at et kildeopptak på Watch blir tolket som et ledig iPhone-opptak bare fordi overføringen er forsinket.
- Dette er en kontroll av eksisterende opptakere, ikke en ekstra HealthKit-sesjon eller nytt lagret øktobjekt. Regresjonstester dekker samtidige kilder og oppstartsforsøk. Identitet og samtykke på iPad er uendret.
- Full iPhone/iPad/Watch/HealthKit-reell verifikasjon og samkjørt CI kreves fortsatt.

## 2.2.6 – én aktivitetssikker Audio Coach-policy også direkte på Watch

- Watch sin eksisterende `evaluateCustomAudioCoachRules` tar nå generiske tid-, puls- og gyldige distanseregler gjennom samme `ATHLTHAudioCoachSportPolicy` som iPhone sitt speil. Sykling og roing kan få målt distanse; HIIT, yoga, meditasjon og andre tidsstyrte økter kan få tid og faktisk målt puls uten å få løpspace/rute/PR.
- Styrke beholder egen ekte sett-/øvelseskontekst, men blandingsregler med pace eller løpe-PR filtreres for å unngå misvisende lyd. Standard distansemilepæler og gjennomsnittspace er begrenset til relevante treningsformer.
- Opprinnelig Watch HealthKit-session, lydleie, samtykke og opptakslag er uendret; ingen ny TTS- eller journalmotor. Regresjonstester dekker sykling, roing, HIIT, yoga og styrke. Krever fortsatt samme-commit CI og fysisk lydtest.

## 2.2.6 – meditasjon, aktivitetsrelevante manuelle felt og tryggere iPad-lesing

- Meditasjonsblokker bruker egen `ATHLTHWorkoutSportMode.meditation`-presentasjon innen den eksisterende bevegelighets-/restitusjonsmotoren, uten ny helseopptaker. Quick Train tilbyr kun manuelt distansefelt for aktiviteter med distanse, så yoga/HIIT/sirkel får ikke et misvisende kilometerfelt.
- Sportikon i privat iPad-snapshot gjenbruker nøyaktig samme aktivitetspolicy som de øvrige liveflatene. Den eksisterende iPad-leseren sanitiserer nå også mottatte snapshot etter å ha kontrollert friskhet og konto, ikke bare utgående snapshot fra iPhone. En eldre/ugyldig synkpakke med manuelle sensorfelt kan dermed ikke bli vist som verifisert GPS/puls.
- Regresjonstester dekker meditasjon og sportikon. Ingen nye historier, migreringer, HealthKit-writers eller TestFlight-opplasting.

## 2.2.6 – sikker opptaksplass ved Watch-oppstart uten livespeil

- `ATHLTHUniversalActiveCapture.current` kan ikke lenger returnere «ingen aktiv økt» når original Apple Watch faktisk opptar HealthKit-plassen, men iPhone ennå ikke har mottatt et gyldig speil. Ingen ny iPhone-økt eller duplikatjournal kan startes på grunnlag av et slikt tomt livesignal.
- En allerede eksisterende styrkejournal som beviselig eies av Apple Watch kan fortsatt vises mens Watch er aktiv. Konflikt med iPhone-løp eller manuell tidtaker avvises. Original ID, klokke, checkpoint og eier beholdes, og etterfølgende gyldig Watch-snapshot kan gjenopprettes på normal måte.
- Nye policy-XCTest dekker fraværende speil, aktiv Watch, motstridende iPhone-kilde og legitim Watch-eid styrke. Full fysisk HealthKit / iPhone / Watch-verifikasjon kreves fortsatt.

## 2.2.6 – iPad-livekort med riktig sykkel- og romåling

- iPad sin eksisterende private livevisning velger nå sportens faktiske måleenheter. Løp/gå beholder min/km, sykling får faktisk beregnet km/t fra målt distanse og aktiv tid, roing får min/500 m; styrke/yoga får ikke tilfeldige distansefelter.
- Kildemerket viser når iPhone-økten bare er en manuell tidtaker, og hastighet/splitt kan da ikke avledes fra oppgitt tid. Kartvisning er tilgjengelig også ved sykkeløkt, forutsatt at opprinnelig kilde deler gyldig GPS-posisjon med samtykke.
- Tester for måleenheter og manglende sensorer er lagt til. Ingen ny iPad HealthKit-opptaker eller endret samtykkelogikk.

## 2.2.6 – bekreftet originalkilde i privat iPad-livekanal

- Den eksisterende, samtykkestyrte iPad-synken skiller nå eksplisitt mellom `watchHealthKit`, `phoneGPS`, `treadmillEstimate`, `strengthLog`, `manualTimer` og `structuredManual`. Dette er ekstra metadata i opprinnelig snapshot, aldri en ekstra opptaker. Gamle snapshots dekodes uten kildemerket.
- Utgående spektator-snapshot fjerner alle puls-, GPS-, kalorier-, pace- og distanseverdier fra tidsstyrte/manuelle økter, også hvis gamle eller feilaktige felt blir satt. Sykling, roing og øvrige treningsformer får ikke løpspace. Korrekt opprinnelig UUID, treningsklokke, samtykke og opptakseier beholdes.
- Regresjonstester dekker manuell kilde og feilaktige idrettsmålinger; samme-commit build og fysiske Watch/iPad/HealthKit-tester gjenstår.

## 2.2.6 – Audio Coach-oppsummering fra samme målesystem for flere idretter

- Den delte, offline talte øktoppsummeringen er nå aktivitetstilpasset. Original Watch-opptaker og iPhone sin eksisterende Watch-mirrorspeaker bruker kildens faktiske sportstype. Løp/gå har min/km, sykling har km/t og roing har tid/500 m når ekte distanse og aktiv tid finnes. Styrke, yoga, HIIT og annen trening får ikke oppdiktet løpsdistanse eller pace.
- Eksisterende løpeoppsummering og verifiserte PR-er beholdes; ingen ny stemme-/lydopptaksmotor eller helsejournal opprettes. Regresjonstester dekker løp, sykkel, roing, styrke, yoga og ugyldige målinger.
- Dette oppdaterer avslutningsmeldingen, men ikke hele den aktivitetsspesifikke live Audio Coach-triggerpakken. Fysisk Watch/lydtest og samme-commit CI gjenstår.

## 2.2.6 – Quick Train-tidtaker på samme universelle livekontroll

- Tidsstyrt Quick Train for sykling, roing, HIIT, sirkel, yoga, mobilitet og andre manuelle aktiviteter bruker nå den samme `ATHLTHLiveWorkoutBottomDock` som løping, styrke og den strukturerte øktspilleren. Pause, Fortsett og Avslutt og lagre er aktivitetstilpasset i ett kontrollkort.
- Tidtakeren oppdaterer bare eksisterende `ATHLTHManualTimedCapture` og `CustomQuickWorkoutJournal`; ingen ekstra klokke, HealthKit-sesjon eller historikkskriver. Manuelle kilometer og RPE fortsetter å være merket som manuelle. Etterregistrering beholder egen lagreknapp siden den ikke er en liveøkt.
- Beskyttelse: både pause og lagring er deaktivert før originalt opptak er opprettet. Test dekker sportene, pause-/fortsettikon og deaktivering. Fysisk enhetstest og samlet CI gjenstår.

## 2.2.6 – felles livekontroll og målvisning for alle treningsformer

- Den opprinnelige strukturerte øktspilleren bruker nå `ATHLTHLiveWorkoutBottomDock`, samme felles bunnkontroll som løp/styrke. Én aktivitetsbasert `structuredActivity`-modus gir korrekt progresjonshandling, bekreftet avslutt og blokkposisjon. Pause og EMOM-/AMRAP-blokkering deaktiverer progresjon; eksisterende checkpoint, fullføringsjournal, opptakseier og original workout-ID beholdes.
- `ATHLTHUniversalPlannedTargetPolicy` genererer én planlagt målvisning fra faktiske blokkfelter for alle sportene. Løpspace/stigning vises ikke som treningsmål for roing/trapp. Styrke får reps og kg, HIIT/sirkel får tid/sone/RPE, og tekstinstruksjoner får ingen oppdiktet treningsmålverdi. Alle disse dataene er planlagte mål – aldri sensormålte resultater.
- Regresjonstester for felles dock, måltyper og alle sporter er lagt til. Dette er ingen ny sensor-writer eller datamigrering. Krever full samme-commit CI og fysiske iPhone/iPad/Watch/HealthKit-prøver før TestFlight.

## 2.2.6 – aktivitetsspesifikk styring fra én felles treningsmotor

- Den eksisterende blokk- og opptaksmotoren får nå én delt `ATHLTHWorkoutSportMode`-tolkning for løping, gåing, styrke, sykling, roing, trappetrening, HIIT, sirkel, funksjonell trening, yoga, mobilitet og øvrige aktiviteter. Både planlagt live-ruting, manuell iPhone-tidtaker og verifisert Watch-projeksjon bruker samme klassifisering av aktivitet til eksisterende motor. Det opprettes ingen ekstra HealthKit-opptak eller skrivejournal.
- Strukturert livekort viser sportens riktige navn og ikon, sportstilpasset «neste»-handling og planlagte mål for taggede aktiviteter, ikke «Veiledning» uten innhold. Kun faktisk lagrede mål for tid, distanse, pulssone og RPE vises. Ingen GPS, puls eller distanse fabrikeres av manuell tid.
- Nye regresjonstester dekker sportstag, opprinnelig øktidentitet, samstemt ruting og manuell aktivitetstolkning. Full fysisk HealthKit/iPhone/iPad/Watch-test og samlet release-CI gjenstår. Det er fortsatt ikke én migrert sensor-writer for alle treningsformer, og TestFlight er ikke autorisert.

## 2.2.6 – deduplicate the same recorded HealthKit session

Watch completion relays may arrive twice after reconnection, sometimes with a different transfer receipt ID even though the saved HKWorkout UUID is identical. AppleWatchConnectionStore now compares the actual recorded HealthKit UUID, or the original ATHLTH universal ID when HealthKit UUID is missing. Handled source identities survive app restart in a separate backward-compatible local list, and recovered pending queues collapse repeated copies before they can create duplicate calendar, strength or workout history. Legacy results with no source identity still use the prior receipt-only guard. Receipts continue to be saved before queue dedup. Targeted XCTest now includes source-owner/offline-queue regressions. No secondary HealthKit writer or history migration.

## 2.2.6 – one shared recording slot including pre-mirror Watch activity

The global recording arbiter now observes the original AppleWatchConnectionStore through a weak reference. An active Watch HealthKit workout or launch preflight occupies the same recording slot before iPhone mirroring appears. iPhone run/walk, strength, calendar and Quick Train retain the original launch reservation. The identity-matching Watch strength recovery exception remains. Tests cover the pre-mirror occupied slot. No new HealthKit writer or duplicated history.

## 2.2.6 – konto-sperre ved universell Watch-gjenoppretting

Universell lokal øktprojeksjon krever nå bekreftet opprinnelig Watch-eier lik aktivt kontobruker-ID før et Watch-livespeil blir returnert. Et loginskifte eller et eldre Watch-snapshot uten lagret eier gir ikke tilgang til forrige brukers treningsdata, og opptaksplassen blir fortsatt behandlet som opptatt i stedet for å starte ny økt. Test dekker samme konto, annen konto og manglende eierbevis. Ingen ekstra HealthKit-writer.

## 2.2.6 – identitetsbevarende, privat Watch-til-iPad-relé

iPhone-reléet til den eksisterende iPad-livespektatoren bruker nå den opprinnelige bekreftede Watch-økts-ID-en, ikke en ny tilfeldig iPhone-generert ID. Dette beholder samme visnings-/samtykkekontekst etter gjenoppkobling. Eldre Watch-økter uten ID får fremdeles en lokalt midlertidig identitet uten at det endrer HealthKit eller historikk.

Watch-livesnapshotet inkluderer valgfritt konto-ID-en som ble fanget ved faktisk HKWorkoutSession-start. iPad-reléet krever dokumentert samme konto før private Watch-målinger deles; gamle snapshots uten eieridentitet kan ikke autorisere deling. Motstridende Watch/strength-ID-er avvises. Tester dekker eier, avbrudd, pause og identitetskonflikt. Fysiske samtykke-/frakoblingstester og samme-commit CI gjenstår.

## 2.2.6 – Watch-resultat og livespeil for samme opprinnelige opptak

- Livepakker med en bekreftet universell Watch-ID kan nå ikke lenger erstattes av forsinkede pakker som mangler ID eller tilhører en annen Watch-økt. Dette gjelder alle native aktivitetskategorier, ikke bare styrke.
- Fullført Watch-resultat kan bare avslutte den aktive livevisningen når original-UUID stemmer. Eldre Watch-resultater uten ID beholder eksisterende streng klokkesammenligning; de tillegges ikke en oppdiktet ID.
- Styrkefullføring krever også at en oppgitt universell ID er lik den opprinnelige styrkelogg-ID-en. Regresjonstester dekker forsinket offline-replay og motstridende UUID.
- Dette samler identitet og livssyklus, men overfører ikke sensoropptaket til en ny eller parallell HealthKit-writer.

## 2.2.6 – stabil original Watch-ID for alle støttede native idretter

Watch-opptak bruker nå én ATHLTH-øktidentitet per faktisk HealthKit-opptak. For styrke er ID lik original styrkelogg-ID; for løping, gåing, sykling, roing, trapper, HIIT, funksjonell, yoga og annet lages ID-en bare på Watch ved ny sesjon. ID lagres i det opprinnelige recovery-checkpointet, sends med live-snapshotet og det ferdige Watch-resultatet. HealthKit-UUID og sluttresultat-ID forblir separate. En gammel eller uleselig recovery uten verifiserbar ID får aldri automatisk ny ID fra iPhone.

Universalmotoren bruker Watch sin bekreftede aktive økttid og kan vise alle støttede Watch-idretter uten å åpne en ekstra HKWorkoutSession. Mismatch i styrke-ID, umulige tidsmålinger, gamle snapshots og økter uten verifisert ID avvises. Ingen duplisert historikk eller endret resultatskriver. Krever samme-commit full CI og fysisk Watch HealthKit-verifikasjon før produksjon.

## 2.2.6 – én identitet for bekreftet Watch-styrke før iPhone-sjekkpunkt

- Universell aktiv økttilstand kan nå lese et nylig bekreftet Watch-speil for styrke direkte fra faktisk Watch UUID, HealthKit-aktiv tid og startklokke. Dette er én skrivebeskyttet visning av originalt Watch-opptak, aldri en ekstra økt, lokal journal eller HealthKit-writer.
- Watch-økter med manglende UUID, gammel sensorstatus, feil idrett, avsluttet tilstand eller umulig aktiv tid forblir beskyttet som opptatt; de gis ikke en oppdiktet økt-ID.
- Når den opprinnelige iPhone-styrkeloggen allerede finnes, brukes den etter eksisterende streng same-ID/same-owner validering. Nye XCTest verifiserer Watch UUID, pause, HealthKit-tid og ugyldige prøver.
- Generiske Watch-idretter uten originalt ATHLTH-workout-ID kan ennå ikke projiseres som bekreftet universell aktiv økt. Ingen usikker deduplisering i historikk.

## 2.2.6 – felles faseovergang og komplette øktoppskrifter

- Den strukturerte iPhone-motoren bruker nå en egen validering av den faktiske neste blokken via ATHLTHLiveWorkoutEngineRouter.advance. Bare etterfølgende, unike steg-ID-er i samme opprinnelige økt kan få motoren til å flytte livekursør. Pauser/instruksjoner er ordinære steg, og ingen overgang lager en separat trenings- eller HealthKit-økt.
- Planlagte rene løpeøkter uten instruksjonssteg fortsetter via den opprinnelige sensorregistreringen. Blandede løpe-/styrkeoppskrifter med egne instruksjonssteg sendes ikke til Watch/rent løpeopptak der de kan bli stille utelatt. iPhone bevarer alle blokkene i den eksisterende strukturerte manuelle spilleren. Dette er fortsatt en manuell oppskrift, IKKE et sensorbevis.
- Tester dekker steg-id, rekkefølge, pauser, instruksjoner, ufullstendige Watch-payloads og uendret øktidentitet. Verifiser samme-commit CI før bruk.

## 2.2.6 – samle Watch Today og øvrige opptaksinnganger

Watch Today-filter, klargjøring fra Hjem, direkte start av planlagt løp/gå og Quick Train-Watch-start bruker nå den samme rute- og beleggsbeslutningen. Watch Today tilbyr ikke fleridrettsoppskrifter som vil miste deler av planen eller en custom-idrett med lagret rute som ikke kan overføres. Den ekte Watch-hybridruten beholdes adskilt fra forenklede Watch Today-payloads, men eier fortsatt bare én treningsøkt. Testene verifiserer alle disse avvisningene. Ingen nye sensorkilder/øktopptak.

## ATHLTH 2.2.6 – sikker sammenkobling av opptaksjournaler

- Den universelle lesemotoren og den samtykkestyrte iPad-spektatoren avviser nå motstridende samtidige opptak, i stedet for å plukke én tilfeldig kilde. En Watch-eid styrkeøkt kan speiles ved bekreftet samme opprinnelige UUID og starttid; et annet aktivt iPhone-opptak skal aldri skjules.
- Pending opptaksreservasjon kan ikke behandles som en ekstra ledig økt etter at opptaket begynner.
- Ved gjenåpning av en tidligere innlagt strukturert økt kreves original lesbar checkpoint. Skadet/manglende data overskrives ikke med tom økt eller ny historikk. Bare en faktisk ny start kan opprette første checkpoint.
- Nye rene regresjonstester dekker konflikt, Watch-identitet, pause og trygg gjenoppretting. Full iOS/iPad/watchOS/HealthKit test foreligger fortsatt ikke.

## 2.2.6 – én felles opptaks- og planrute

`ATHLTHPlannedWorkoutCaptureRoute.resolve` er nå kanonisk beslutningspunkt for Hjem-kalenderens planlagte økter. Blokker med flere aktiviteter kan ikke lenger bli feilaktig startet som bare løping, styrke eller en annen Watch-idrett. En gyldig løp/styrke-hybrid bruker samme originale styrkehybridjournal; en økt med løping og yoga blir en strukturert manuell iPhone-økt eller avvist på Watch. Støttede enkle idretter beholder eksisterende Watch HealthKit-opptaker. `ATHLTHUniversalWorkoutAdmission.isOccupied` samler åtte opptakstilstander og brukes av Train, Custom Quick, Hjem-kalender, planstart og styrke. Endelig start krever fortsatt den opprinnelige globale opptaksreservasjonen. Ingen ny HKWorkoutSession, GPS-kilde, historikkfil eller datamigrering er introdusert. Må testes på samme commit og fysiske enheter før release.

## 2.2.6 – manuelle økter i iPad-spektator og felles startkontroll

- iPhone-tidsstyrte Custom Quick-økter for alle aktiviteter vises nå i den **eksisterende samtykkestyrte** iPad-livekanalen. Økt-ID, start, aktiv tid, drag og pause kommer fra original tidscheckpoint via universalmotorens projeksjon.
- Tidsregistrering gir ikke grunnlag for å publisere puls, kalorier, GPS, målt distanse, pace eller Spotify-status; disse feltene er fraværende for manuelle økter.
- Train og Custom Quick kontrollerer også startforespørsler som ennå venter på opptaksopprettelse, så en UI-knapp ikke varsler falsk ledig plass.
- En minimert strukturert økt startet utenfor treningsplanen kan gjenfinnes fra Hjem i tillegg til ordinære planøkter. Ingen dobbel fullføring eller ny opptaksjournal opprettes.
- Regresjonstester dekker alle manuelle aktiviteter, 20/10 Tabata, fryst pause, intervallposisjon og fravær av oppdiktede sensorer. Krever samme-commit iPhone/iPad/Watch CI og fysisk test før utgivelse.

## 2.2.6 – Watch-resultater for flere treningsformer

Eldre Watch-resultater uten eksplisitt plan-ID kan nå knyttes til korrekt planlagt sykling, roing, HIIT, trapp, yoga og andre støttede aktiviteter når den eksisterende tre-minuttersregelen finner nøyaktig én gyldig, aktiv plan. Vi matcher aldri en meditasjonsøkt som yoga eller en annen aktivitet som styrke, og lager ingen ekstra historikk.

## 2.2.6 – vedvarende pause og aktiv tidsmåling

Strukturert iPhone-motor har nå én pauseklokke i originalcheckpointen. Pause stopper deltrinns-/EMOM-/AMRAP-klokken, gjenoppta forskyver deres eksisterende ankere, og aktiv varighet i sammendraget ekskluderer brukerpauser. Historiske checkpoints og fullføringer dekodes via valgfrie felt. Universalmotor og privat iPad-spektator ser samme pause og fryste tid. Ugyldig pause beskyttes, ikke overstyres. Ingen separat HealthKit-opptaker eller ekstra historikk.

## 2.2.6 – felles aktiv økttilstand for alle eksisterende treningsformer

- Ny skrivebeskyttet ATHLTHUniversalActiveCapture projiserer fire eksisterende originalkilder: iPhone-løp/gå, styrkelogg, Custom Quick iPhone-tidtaker og strukturert øktcheckpoint. Det opprettes ikke nye HealthKit-sesjoner, historikklagre eller kopier av en fullført økt.
- Felles live-tilstand inneholder stabil økt-ID, kilde, aktivitet, motor, fase, faktisk tid og (når lagret) kronologisk steg. Alle Custom Quick-aktiviteter, inkludert sykling, roing, HIIT, sirkel, funksjonell trening, yoga, mobilitet og øvrige typer, får samme lesemodell som løp/styrke.
- For tidsstyrte intervaller utledes drag og hvile fra den opprinnelige lagrede konfigurasjonen. Manuelt registrert tid og data merkes fortsatt som manuelle: ingen oppdiktet GPS, puls, distanse eller Apple Health-opptak.
- Samtidige urelaterte kilder avvises. Den samme historiske løp+styrke-hybriden kan fremdeles ha to avledede visninger av ett opptak. En uleselig eller annen konto-checkpoint blir ikke behandlet som ledig opptaksplass.
- Custom Quick kan ikke gjenoppta en eksisterende tidtaker med endrede runder, drag-/pausetid, varighetsmål eller tittel selv om aktivitet og metode er like. Original økt-ID og tid bevares.
- Train-kortet bruker den felles aktivitetstolkningen og tidsprojeksjonen. Nye XCTest-regresjoner dekker aktivitetsbredde, drag/hvile, fryst pause, blandede strukturer, motstridende opptak, korrupt kilde og kontoisolasjon. Motor-XCTest-workflowen inkluderer testene.
- Dette er første lesende integrasjonssteg, ikke en komplett sensor-/opptaksmigrering: løpe-/styrke-/tidsmotorer er fortsatt autoritative. iPad/Watch/HealthKit/Spotify krever full CI og fysisk test før produksjon. Ingen TestFlight-opplasting autorisert for 2.2.6.

# ATHLTH: én planleggingsmotor, tilpassede live-motorer

## Overgang til ATHLTH 2.2.6 (20. november 2026)

- Ny aktiv gren `release/v2.2.6`, markedsversjon 2.2.6 og build 134, opprettet fra den uendrede 2.2.5-snapshotten `bc23640f389fcf3d7cdb558a78fb6fcaefca1ac5`.
- 2.2.5 er bevart i `locked/v2.2.5` og `backup/v2.2.5-locked-before-v2.2.6-20261120`. Forrige kildecommit `fcc832a4e2cbe3297eea6a8bacb8438aa3bbb525` bestod samme-commit iOS, watchOS, backend, iPhone/iPad og iPad 11/13-tommers simulatorprøver. 2.2.5 TestFlight-workflow på triggercommit `bc23640f389fcf3d7cdb558a78fb6fcaefca1ac5` var fortsatt i gang ved grenopprettelse; verifiser App Store Connect-upload separat.
- Videre motorutvikling og feilretting skjer bare på 2.2.6, med én autoritativ treningsregistrering og uendret historikk. Fysiske iPhone/iPad/Watch GPS-, HealthKit-, Spotify- og Audio Coach-tester er ikke dokumentert. Ny 2.2.6 TestFlight-opplasting krever egen autorisasjon.

Historisk status (1.9.1): planprosjeksjon, UI-ruting og begrenset fellesopptak for planlagt styrke + tidsstyrt tredemølle er koblet inn i kalendervisningen. Kode-/simulatortester er satt opp; fysisk Watch-verifikasjon gjenstår.

## 2.2.6 – felles aktivitetstolkning på tvers av treningsformer (20.11.2026)

- `ATHLTHUnifiedActivityProfile` er ett, rent og skrivebeskyttet klassifiseringslag for den eksisterende blokktidslinjen. Plan Studio, Coach-blueprints, treningsbibliotekets filter og aktivitetsvelger deler nå samme regler.
- Løping, gåing, styrke, sykling, yoga, meditasjon og mobilitet identifiseres fra lagrede blokker eller eksplisitte eldre kategorier, aldri fra øktnavn. Hybrid identifiseres når en plan inneholder mer enn én aktiv treningsform. Aktiv gåpause i et løp blir ikke en falsk hybrid.
- `ATHLTHUnifiedWorkout.apply` beholder én kilde-ID, originale blokker og én lagret plan. `ATHLTHPlanStructuredWorkoutBlueprint.applying` bruker nå aktivitetsklassen fra faktisk oppskrift, også hvis den opprinnelige valgknappen har en annen kind. Det opprettes ikke parallelle øvelses-/løpeoppskrifter.
- Eldre enkle sykkel- og velværeøkter med eksplisitt kategori og tidsmål kan projiseres til én tidsstyrt `.note`-blokk for planredigering. Det er en visning av eksisterende data, ikke en ny GPS-/HealthKit-måling, ny historikk eller automatisk opptaksstart.
- Dette **sammenstiller plan-, bibliotek- og visningslogikk, men er IKKE en ferdig felles opptaksmotor for sykling/yoga/meditasjon**. Løping og styrke har fortsatt ulike autoritative opptaks-/historikklagre. Watch har egne sensor- og opptakskontrollere. Ingen fysiske enhetstester eller full samme-commit CI er utført på 2.2.6-koden.
- `ATHLTHWorkoutCaptureAdmission.requireSupportedStrengthCapture` brukes nå av `WorkoutLaunchCoordinator.startStrength` **før** `ATHLTHWorkoutRecordingArbiter.reserveLaunch`, sosial invitasjon, iPad-relé og Watch HealthKit. Rent styrkeopptak og eksisterende validert løp+styrke-hybrid tillates; sykling, yoga, meditasjon og rene løpeøkter kan ikke feilregistreres som styrke. Det finnes nå målrettede regresjoner for tillatte og avviste starter.
- Neste integrasjonsdel er å bygge korrekt per-aktivitet capture adapter for sykling og velvære (med sensorer og samtykker), koblet til samme opptaksreservasjon. Hittil er denne opptakstypen IKKE implementert eller fysisk verifisert. Ingen shadow-økt eller stille konvertering til løping/styrke.
- Nye XCTest-regresjoner dekker hybridklassifisering, aktiv gåpause, legacy-walking, sykkel/styrke, yoga/meditasjon, legacy Codable og ingen duplisert oppskrift. De står for senere samlet testing.

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


### 2.2.6 – strukturert økt får felles opptakssperre og feilkontrollert historikk (20.11.2026)

- `ATHLTHStructuredCaptureAdmission` finner kontoens eksisterende, uferdige `structuredWorkoutInProgress.v1`-checkpoints ved innlogging og reserverer samme opptaksslot som løp, styrke, Watch og manuell iPhone-tidtaker. Det er kun en kontroll over ORIGINALEN, ingen ny historikk eller ny HealthKit-økt.
- Gyldige, men eldre enn syv dager strukturerte checkpoints beholdes på disk uten å hindre helt nye økter. Ukjente, uleselige, fremtidige eller motstridende aktive checkpoints blokkerer derimot ny start inntil korrekt gjenoppretting. Dette forhindrer permanent brukerblokkering fra en gammel, gyldig økt.
- Start, fullføring og eksplisitt forkasting validerer konto og økt-ID. En minimert økt beholder opptakssperren. Train viser en fortsett-handling for eksisterende plan, men et uleselig/ukjent checkpoint blir aldri automatisk overskrevet. Et nytt valgfritt `completionID` i checkpointet beholdes ved gjenoppretting, slik at fullføringen ikke dupliseres hvis journalen ble skrevet før en krasj/stanset cleanup.
- Tidligere enkle planlagte sykkel-, yoga- og meditasjonsøkter med eksplisitt kategori og varighet kan nå åpnes fra Train som ett tidsstyrt `StructuredWorkoutSessionView`. En *skrivebeskyttet* blokkprojeksjon brukes kun i spilleren; opprinnelig plan, ID, historikk og HealthKit-lagring endres ikke. Tester kontrollerer riktig varighet og fravær av oppdiktet distanse/fart.
- Train overfører nå faktisk kildeplan-ID til `StructuredWorkoutSessionView` når originaløkten ligger i treningsplanen. Fullføringsjournalen beholder dermed planrelasjonen uten å gjette ut fra tittel.
- `StructuredWorkoutCompletionStore.save` leser tilbake lagret resultat før det meldes fullført. Hvis lagring feiler, beholdes checkpointet, og brukeren ser en feil i stedet for et falskt vellykket resultat. Også checkpoint-skriving og sletting er kontrollert.
- Dette er en trygg samordning av eksisterende strukturert iPhone-spiller; ikke full sensor-/HealthKit-implementering for alle aktivitetskategorier. Regresjonstester og full samme-commit CI/fysiske iPhone/Watch/iPad-tester gjenstår.

### 2.2.6 – samme opptaksreservasjon for iPhone-tidsmålte aktiviteter (20.11.2026)

- `ATHLTHManualTimedCapture` er en kontoavgrenset, gjenopprettbar tidtaker for eksisterende CustomQuick-aktiviteter (sykling, yoga, mobilitet, roing, HIIT, øvrige). Den erstatter ikke `CustomQuickWorkoutJournal` som autoritativ ferdighistorikk og lager ikke en HealthKit-økt.
- Ett aktivt tidscheckpoint blokkerer `ATHLTHWorkoutRecordingArbiter.reserveLaunch`, `mayStartRunning`, `mayStartStrength`, Watch-bootstrapping og tilgjengelig opptaksslot. Dermed kan ikke en ny løpe-/styrkeøkt starte over den aktive iPhone-tidtakeren. Et allerede aktivt opptak hindrer tidsstarten.
- Tidsmålt aktivitet får stabil ID fra første start. Pause, fortsett, forlenget tidsgrense og ferdig/avbryt blir verifisert mot kontoens eget checkpoint. Den opprinnelige metoden, intervall-/pausevarigheten og antall drag lagres også, så gjenoppretting ikke bytter til standardverdier. Prosessavslutning, bakgrunn og utlogging forkaster **ikke** ulagrede tidsdata, men en annen konto kan ikke overta økten.
- `CustomQuickWorkoutJournal.save` bekrefter nå lagring bare når originalrecord kan leses tilbake; feil sender ikke feilaktig treningsoppdateringssignal eller viser «lagret». Nytt forsøk bruker samme ID og lager ikke to resultater.
- Manuell distanse, opplevd innsats og tidsmåling forblir ærlig merket som manuelt/uverifisert. Dette er **ikke** et løfte om GPS, sanntidspuls, bakgrunnsopptak på iOS eller automatisk Apple Health-eksport. Dedikert sensor-/HealthKit-overføringsadapter for sykkel/yoga/mobilitet krever egen implementering og fysiske enhetstester.
- Train viser nå aktiv tidsmålt økt med egen Fortsett-handling og samme opprinnelige konfigurasjon. Quick Custom/sykling/fri trening kan også gjenoppta korrekt aktiv tidsøkt. Watch Quick Custom holder nå universell launch-reservasjon gjennom asynkron Watch-start og krever at Watch er ledig. Ingen skjult samtidig start.
- Nye regresjoner verifiserer opptaksblokkering, konto-/krasj-gjenoppretting, korrupte checkpoints, ikke-overtakelse av annen aktivitet og idempotent historikk. Full CI og fysisk test er utsatt etter brukerens ønske.

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

### Fase 4 – varig kvitteringsjournal for iPad-fjernstart (19.11.2026)

- `WorkoutDeviceRelayStore` journalfører ID-en til en **allerede vellykket**
  fjernstart lokalt før nettverkskvitteringen. Journalen er avgrenset til
  innlogget bruker og fysisk iPhone. Den lagrer **ikke** øktoppskrift,
  helseverdier eller et alternativt HealthKit-opptak.
- Ved oppstart, sanntids-reconnect og manuell innhenting forsøkes utestående
  kvitteringer sendt til serveren **før** nye startkommandoer hentes.
  En kvitteringsfeil beholder journalposten; selve Watch-/iPhone-starten
  blir aldri spilt av på nytt bare for å kvittere.
- Kommandoer valideres mot avsender, målenhet, type, skjema og utløpstid
  før noen HealthKit-sideeffekt. Regresjonstesten
  `WorkoutDeviceRelayClaimPolicyTests` er koblet inn i målrettet XCTest-CI.
- **Begrensning:** lokal UserDefaults-journal er en ekstra
  krasj-/nettverksbeskyttelse, ikke en distribuert eksakt-én-gang-garanti.
  Dersom prosessen avsluttes akkurat mellom en vellykket ekstern
  Watch-start og lokal journalføring, kreves fortsatt en autoritativ
  Watch-status-/serverrekonsiliering før kommandoen kan anses endelig
  ferdig. Fysisk Watch/iPad-testing og grønn samme-commit CI gjenstår.

### Fase 7 – resultatkø ved konkurrerende Watch-/iPhone-økter

- Resultater med `strengthSnapshot.workoutID` er nå
  styrkeresultater helt til de er korrekt koblet mot eksisterende
  aktiv eller ferdiglagret `StrengthWorkoutLog`. De kan **ikke**
  konverteres til generiske Watch-resultater ved opptakskonflikt.
- En pågående iPhone-økt, uferdig kontogjenoppretting eller en
  samtidig oppstart utsetter kun dette styrkeresultatet i den
  eksisterende durable køen. Andre allerede kvalifiserte
  Watch-resultater kan passere og behandles.
- Planlagt økt får først faktisk Watch-sluttid etter at
  styrkeresultatet er knyttet til varig historikk; tidligere
  oppdaterte kalenderen seg før riktig fullføring var bekreftet.
- Tester dekker konflikt med ny styrkeøkt, senere matching av
  ferdig økt, kontoikke-klar, trygg bootstrap og generiske
  Watch-resultater uten styrkesnapshot.

### Fase 8 – ett klokkegrunnlag i styrke-, hybrid- og livekort

- `StrengthWorkoutLog.elapsedSessionSeconds` er nå den felles,
  rene øktklokken for styrke og hybrid. Tid mellom vanlige sett
  inngår fremdeles, mens dokumentert offline-tid fra iPhone-
  gjenoppretting trekkes fra via et valgfritt, bakoverkompatibelt
  `excludedRecoverySeconds`-felt.
- `StrengthWorkoutStore` samler gjenværende nedetid ved «Fortsett»
  eller «Avslutt» etter gjenoppretting. Dette bevarer den opprinnelige
  økt-ID-en og oppstartstiden. Pågående gjenopprettet iPhone-økt
  vises som `paused` inntil brukeren bekrefter fortsettelse.
- Felles session-projeksjon, live styrkekort, header,
  avslutningsdialog og resultatoppsummering bruker samme varighet.
  Watch-eide HealthKit-økter får ikke påført en kunstig pause.
- Tester verifiserer en times offlineperiode, 45 sekunder faktisk
  innsats før avbrudd, korrekt fortsettelse og stabil økt-ID.

### Fase 8 – HealthKit får nøyaktige recovery-pausehendelser

- Phone-eide styrkeøkter lagrer nå eksakte `DateInterval` for
  dokumenterte avbrudd etter krasjgjenoppretting. Overlappende/
  doble sjekkpunkter slås sammen idempotent. Eldre loggformat
  leses videre uten krav om migrering.
- Den ordinære iPhone-avslutningen skriver korrigert aktiv varighet
  til styrkehistorikken, ikke rå veggklokke fra første start.
- `HealthKitManager.saveManualStrengthWorkout` sender pause- og
  resume-hendelser til samme HKWorkoutBuilder før lagring, slik at
  Apple Health kan ekskludere dokumentert offline-tid samtidig
  som sann start og slutt beholdes. Vanlig pause **mellom sett**
  forblir del av styrkeøkta. Ved feil ved pausehendelsene
  forkastes den ufullstendige HealthKit-byggeren i stedet for å
  lagre et kunstig langt treningstidsrom.
- Tester dekker overlappende avbrudd, idempotens, aktiv økttid og
  at Watch ikke automatisk får tilført phone-offline pauser.
  Verifikasjon på faktisk iPhone/Watch og samme-commit CI gjenstår.

### Fase 5 og 7 – stabil øktidentitet i live Watch-speiling

- `WatchWorkoutLiveSnapshot` inneholder nå valgfri
  `strengthWorkoutID`, sendt fra den eksisterende Watch-styrkeloggen
  i hvert live snapshot. Den er den samme som `StrengthWorkoutLog.id`,
  og skaper ikke en ekstra HealthKit-sesjon.
- Speilet status fra en annen styrkeøkt kan ikke overskrive nyere
  status når begge snapshot har stabil ID. Avslutning av iPhone
  styrkelogg fra en speilet `completed` krever riktig økt-ID,
  riktig aktivitet og tilsvarende HealthKit-starttid.
- Eldre Watch-build uten ID kan fortsatt levere fullføringsstatus
  ved bekreftet start innen 15 sekunder, men manglende start eller
  3-minutters tilfeldige treff avvises. WatchWorkoutResult med
  økt-ID i snapshot forblir primær varig fullføring.
- Tester dekker feil ID, gammel økt, legacy-speiling, manglende
  start og sen payload fra annen Watch-økt.

### Fase 4 – speilet Apple Watch-opptak er ikke en ledig opptaksplass

- `ATHLTHWorkoutRecordingArbiter` inkluderer nå den eksisterende
  HealthKit Watch-speilingen når den avgjør om løp, gå eller styrke
  kan starte. Ingen ny lokal Quick Train kan starte oppå et
  aktivt Watch-opptak bare fordi en lokal checkpoint mangler.
- Watch-styrke kan fortsatt restaureres fra sin opprinnelige
  snapshot når aktivitet, starttid og stabil økt-ID stemmer
  med den speilede Watch-økten. Uidentifisert mirror, annen
  Watch-aktivitet og andre styrkeøkter avvises i opptaksgrensen.
- Den aktive asynkrone oppstartsreservasjonen beholdes til
  den valgte Watch/iPhone-lokalloggen er opprettet.
- Tester dekker speilet Watch-styrke, Watch-løp, feil ID,
  gammel økt og legitim offline-gjenoppretting.

### Fase 7 – HealthKit-backfill fra iPhone uten å overskrive «siste økt»

- Den asynkrone HealthKit-UUID-en for iPhone-styrke knyttes nå
  atomisk til **nøyaktig** fullført iPhone-treningslogg på riktig konto.
  Feil konto, slettet konto, aktiv økt og fremmed HealthKit-UUID
  avvises. Gjentatt kvittering med samme UUID er idempotent.
- Oppdatering av en eldre økt kan ikke lenger skrive over den
  nyeste fullføringsjournalen som brukes ved krasjgjenoppretting.
  Journalen oppdateres bare hvis den allerede peker til samme økt.
- Regresjonstestene fullfører to separate styrkeøkter, mottar sent
  HealthKit-svar på den første og verifiserer at den andre
  fortsatt er siste fullførte økt.

### Fase 5/7 – Watch-ferdigmelding krever riktig styrke-ID

- `WorkoutMirroringStore.reconcileCompletedWatchWorkout` sjekker nå
  både HealthKit-starttid og stabil `strengthWorkoutID` når
  Watch sender et fullført styrkeresultat. En gammel ferdigmelding
  kan dermed ikke avslutte en nyere speilet Watch-økt med samme
  aktivitet og omtrent samtidig start.
- Når den nye speilingen har en stabil økt-ID, avvises en
  sluttmelding uten identitet. Eldre Watch-speilinger uten ID
  beholder den eksisterende strenge starttidskontrollen.
- En allerede fullført Watch-økt med korrekt økt-ID kan fremdeles
  rekonstruere iPhone-styrkehistorikk mens mirroring-flagget
  holder på å avsluttes. Det skaper ingen ny HealthKit-økt.
- Tester dekker feil ID, manglende ID, ugyldig slutttid,
  legacy Watch og korrekt gjenoppretting etter fullføring.

### Fase 5/6 – gammel inaktiv Watch-status skal ikke stenge ny liveøkt

- `reconcileInactiveWatchActivity` krever nå at en eksplisitt
  «inaktiv»-melding er minst like ny som **siste godkjente**
  Watch-snapshot, ikke bare nyere enn øktens opprinnelige start.
  Dermed kan en forsinket melding fra forrige økt ikke avslutte
  en nyere aktiv HealthKit-speiling eller Dynamic Island-visning.
- Håndterer manglende start, ugyldig dato, allerede avsluttet
  økt og aktiv Watch-status som ikke bevis for slutt.
- Tester dekker gammel versus ny status og fullført økt.
  Fortsatt nødvendig med reell iPhone/Watch-reconnect-test.

### Fase 7 – fjern dobbelt HealthKit-skriving fra styrke-fullføring

- Det ble identifisert **to samtidige** manuelle HealthKit-skriveveier
  ved fullføring av iPhone-styrke: `ActiveStrengthWorkoutView` og
  `ATHLTHApp.handleStrengthWorkoutCompletion`. UI-veien er fjernet;
  den sentrale fullføringshåndteringen er nå eneansvarlig for
  HealthKit-registreringen. Én eksisterende `StrengthWorkoutLog`
  og samme stabile økt-ID beholdes.
- Central writer viderefører dokumenterte `recoveryPauseIntervals`
  til `HealthKitManager` og knytter den returnerte HealthKit-UUID
  atomisk til samme fullførte logg og riktig innlogget konto.
- `onChange` observerer nå **fullført økt-ID**, ikke hele objektet,
  slik at etterleverte puls-/HealthKit-målinger ikke starter ny
  fullføringsflyt, nye utfordringer, trofeer eller sosiale sideeffekter.
- `HealthKitManager` beskytter overlappende asynkrone skrivinger
  for samme økt og søker etter det eksisterende synkroniserte
  HealthKit-opptaket før et nytt bygges. Stabilt
  `HKMetadataKeySyncIdentifier` støtter gjenbruk etter appavbrudd.
- Test dekker gjentatte skrivetillatelsesforespørsler, parallell
  skriving for en annen økt og ny prøve etter ferdig skriv.
  Watch/HealthKit må fortsatt testes på faktiske enheter.


### Fase 4 — fjernstart og kommandokø (19.11.2026)

Fjernkommandoer valideres nå mot serverens avsender, mål, aktivitet, format,
utløp, **faktisk claim-enhet** og terminalstatus før start. Bare én vellykket
fjernstart utføres per køtømming; neste økt må ikke startes mens Watch/HealthKit
etablerer forrige. Kontoendring kontrolleres også etter asynkrone operasjoner.
Ved vellykket start journalføres kommando-ID lokalt før serverkvittering;
serverkvittering som feiler må aldri automatisk føre til ny HealthKit-start.

**Gjenstående sikkerhetsgrense:** Et krasj mellom faktisk Watch-oppstart og
lokal journalføring kan fortsatt gi uavklart server-claim. Ikke innfør
automatisk gjenkjøring av slike claims uten verifisert Watch-/HealthKit-status.
Krev iPhone/iPad/Watch-akseptanse og samme-commit grønne CI-jobber før release.


### Fase 4 – crash-vindu ved fjernstart (19.11.2026)

Før iPhone suspenderer i asynkron Watch-/HealthKit-start journalføres kommando-ID
som **usikker start** per konto og fysisk enhet. Ved vellykket start flyttes
ID-en til den eksisterende kvitteringsjournalen før serverkall. Selv om asynkron oppstart kaster feil, beholdes den usikre posten fordi
Watch kan ha akseptert kommandoen før feilen. Ved prosessdød, kansellering eller
kontobytte kan utfallet heller **ikke** antas å være feil. Køen blokkeres derfor til
faktisk Watch-/HealthKit-status er rekonsiliert. Dette er en bevisst
fail-closed-sperre: den hindrer dobbeltopptak, men kan kreve manuell avklaring
etter krasj. Automatisk, verifisert rekonsiliering av usikre starter er fortsatt
**ikke implementert** og må på plass før fase 4 godkjennes. Ingen ny
HealthKit-opptakstype, historikkpost eller datamigrering er innført.

### Fase 4 – trygg kvittering av fjernstart (19.11.2026)

- Den lokale ID-journalen for vellykket fjernstart blir kontrollert **før**
  en serverclaim kan avvises som utløpt eller behandles på nytt. Et kjent
  startforsøk blir aldri spilt av igjen bare for å reparere serverstatus.
- Utestående kvitteringer må avklares før en ny serverkommando claim-es.
  Dersom nettverket hindrer kvittering, stoppes købehandlingen i stedet
  for å forsøke neste HealthKit-/Watch-start.
- iPhone kan ikke lenger rapportere en avbrutt styrkeoppstart
  (`startStrength == false`) som en vellykket fjernstart. Et feilaktig
  kall på en annen enhet enn iPhone avvises eksplisitt.
- Sikkerhetsbegrensning: et prosesskrasj mellom ekstern Watch-start
  og lokal journalføring krever fremdeles autoritativ
  Watch-/serverrekonsiliering før eksakt-én-gang kan garanteres.
  Samme-commit iOS-/Watch-CI og fysisk treenhetstest gjenstår.

### Fase 4 – sammenhengende iPad → iPhone → Apple Watch-identitet (19.11.2026)

- Nye iPad-fjernstarter bruker eksisterende `client_request_id` som én
  stabil korrelasjons-ID i serverposten og payloaden. iPhone avviser en
  serverclaim som ikke matcher payloadens ID. Eldre payloads uten feltet
  kan fremdeles dekodes.
- For Watch-mål føres samme ID gjennom felles oppstartskoordinator for
  løping, gåing og styrke. iPhone krever en direkte WatchConnectivity-ACK
  med eksakt ID **før** HealthKit får starte Watch-appen. Manglende
  rekkevidde, timeout eller avvikende ACK avviser fjernstarten; det er
  bevisst fail-closed og kan kreve at brukeren åpner Watch-appen.
- Watch lagrer en kortvarig, typebundet ventende start-ID før ACK og
  knytter den til faktisk HealthKit-økt når denne etableres. ID-en
  lagres med Watch sin eksisterende recovery-checkpoint, og kan
  rapporteres i den aktive øktens aktivitetsstatus. Lokal Watch-økt
  arver aldri ID fra en relékommando.
- Ved appstart og overgang til forgrunn kan iPhone sammenligne en
  uavklart lokal startjournal med **fersk aktiv Watch-status**, og
  kontrollere eksakt serverpost, fysisk telefon, konto, mål og
  forespørsels-ID. Bare eksakt samsvar oppgraderer journalen til
  en bekreftet start; den ordinære serverkvitteringsrutinen gjør resten.
  Ingen gjenoppretting starter en ekstra HealthKit-økt.
- For løp på Watch overstyrer en ekte fjernstart «start manuelt på
  klokken» til umiddelbar start; den kan ikke kvitteres som vellykket
  når bare et forberedelseskort er overført.
- Testdekning: feil ID, manglende ID, feil mål, serverfeil,
  kortvarig token, transport/eldre aktivitetspayload.

**Fortsatt begrensning:** Hvis Watch-økten allerede er avsluttet før
iPhone får en fersk aktivitetsstatus, kan aktiv status alene ikke bevise
historisk gjennomført oppstart. Journalen holdes da uavklart fremfor
å anta suksess/feil. En framtidig fullført Watch-kvittering bør ha
samme ID og HealthKit-workout-UUID, slik at også avsluttede økter kan
gjenopprettes autoritativt. Alle nye endringer krever grønn CI på samme
commit og fysisk iPhone/iPad/Watch-test før fase 4 kan godkjennes.

### Fase 4 – terminal Watch-kvittering og akseptanseport (19.11.2026)

**Implementert i kode (ikke fysisk godkjent):**
- En vellykket Watch-`HKWorkoutBuilder.finishWorkout()` gir
  `WatchWorkoutResult.relayRequestID` ved faktisk HealthKit-lagring,
  sammen med eksisterende `healthKitWorkoutUUID` og Watch-kontoen.
  Eldre/standalone Watch-resultater har `nil`, og kan ikke
  bekrefte en fremmed fjernstart.
- Watch lager en **minimal terminal kvittering** med kun forespørsels-ID,
  resultats-ID, HealthKit-UUID, eier, type og start-/sluttid.
  Den journalføres før ordinær resultatmelding og sendes både direkte
  og via WatchConnectivity sin varige brukerinfo-kø.
  Ved ny Watch-aktivering spilles kvitteringer fra en begrenset
  30-dagers outbox av på nytt. Selve treningsmålingene dupliseres ikke.
- iPhone beholder terminalt bevis **uavhengig av** Watch-resultatets
  eksisterende importkø. En avsluttet økt kan dermed bekrefte en
  tidligere uavklart fjernstart også etter at vanlig historikk-import
  har konsumert resultatet. Kvitteringen begrenses til 128 poster /
  30 dager og brukes kun ved eksakt innlogget konto.
- Rekonsiliering krever både eksakt `client_request_id`, serverpost
  claimet av denne telefonen, samme konto, Watch-mål, kompatibel
  aktivitetstype, ikke-feilet serverpost og starttid etter request.
  Terminalt bevis krever ekte HealthKit-UUID. En annen ferdig økt,
  feil konto, feil aktivitet eller feil UUID kan aldri løse journalen.
- To motstridende HealthKit-resultater med samme request-ID avvises
  som tvetydig dokumentasjon. De slettes ikke for å velge en vilkårlig
  «vinner». Replay av samme kvittering idempotent.
- Dette etablerer **ingen ny HealthKit recording**, duplikat logg eller
  alternativ treningshistorikk; PhoneWorkout/StrengthWorkoutLog og
  Watch-resultatimport forblir autoritative.

**Må verifiseres før fase 4 kan erklæres godkjent:**
1. Samme-commit grønt Build ATHLTH, Train/Hybrid XCTest, backend og
   iPhone-kompatibilitet, inkludert watchOS-kompilering.
2. iPad → iPhone- og iPad → Watch-start for løp, gåing og styrke,
   både fra forgrunn og etter app-frakobling; ett fysisk HealthKit-opptak.
3. Frakobling/krasj før Watch-start, etter start, etter HealthKit-lagring
   og før mottatt serverkvittering; hver tilstand har korrekt journal.
4. Watch allerede avsluttet før iPhone får ny aktivitetsstatus;
   minimal outbox-protokoll og vanlig treningshistorikk fungerer
   uavhengig av meldingsrekkefølge. Ingen dobbel historikk/import.
5. Kontobytte, feil økt-ID, to motstridende UUID-er, gammelt
   heartbeat, iPad-samtykke og ny trening før gammel melding.
6. Fysisk iPhone + iPad + Apple Watch og HealthKit-resultatet må
   kontrolleres, inkludert Watch-app som ikke er i forgrunnen.

**Gjenstående begrensninger:** HealthKit kan i sjeldne tilfeller lagre
en økt rett før Watch-appen krasjer **uten at den rekker å konstruere
terminal kvittering**. Da beholdes usikkerhetsjournalen inntil
autoritativ HealthKit-historikkavklaring; ikke gjett eller start på nytt.
Nye iPad-initierte Watch-starter krever WatchConnectivity-ACK før
HealthKit-start – en sovende/ikke-reachable Watch kan derfor bli
avvist uten at det opprettes en økt. Sikkerhet har prioritet til
fysisk verifisert oppstartshåndtrykk finnes.

Ingen TestFlight-opplasting uten separat uttrykkelig godkjenning.

### Fase 4 – avsluttende lokal iPhone-rekonsiliering (19.11.2026)

- Reléidentiteten er nå et valgfritt, varig felt i den **eksisterende**
  `PhoneWorkout` (løp/gå) og `StrengthWorkoutLog`. Den settes bare når
  en iPad-kommando faktisk skaper en autoritativ lokal økt.
  Eldre registreringer uten `relayRequestID` forblir kompatible og
  kan ikke feilaktig bekrefte en ny fjernstart.
- Den felles `WorkoutLaunchCoordinator` krever at iPhone faktisk har
  opprettet en aktiv økt med eksakt request-ID **før** fjernstart kan
  rapporteres som vellykket. Dette hindrer falsk serverkvittering mens
  en utendørs løpe-/gåøkt fremdeles venter på GPS-tillatelse.
- Ved avbrutt prosess kan reléet kontrollere eksisterende
  `phoneActive`, `phoneHistory`, sluttført iPhone-resultat,
  `StrengthWorkoutStore.activeWorkout` og `workoutHistory` mot
  eksakt serverrequest, riktig konto, aktivitetstype, iPhone-mål
  og starttid. Ingen heuristikk basert på tittel, mal eller plan-ID.
  Apple Watch-eide styrkelogger er **ikke** tilstrekkelig bevis;
  Watch krever sin egen aktive eller terminale HealthKit-kvittering.
- Automatisk avklaring forsøkes ved kald appstart, forgrunn,
  sen Watch-resultatmelding, opprettet iPhone-økt og endret lokal
  historikk. Samtidige callbacks serialiseres; hendelser som kommer
  under en aktiv rekonsiliering utløser en ekstra gjennomgang.
  Watch-probe utføres bare når nødvendig og bare for Watch-mål.
- Ved sikkert bevist eksisterende opptak flyttes serverkommandoen
  fra usikker journal til varig suksesskvittering, og serverreceipt
  forsøkes oppdatert. Verken iPhone eller Watch startes på nytt.
  Uavklarte eller motstridende bevis fortsetter å blokkere ny start.

**Implementeringsstatus:** Fase 4s hovedkode for fjernstart,
krasjsikker lokal journal, kontobytte, Watch- og iPhone-bevis,
offline-kvittering, iPad read-only-status og gjenoppkobling
er nå lagt inn i `release/v2.2.5`. Full aksept krever fortsatt
samme-commit grønn iOS/watchOS/iPad-build, simulator-XCTest og
fysisk treenhetstest med reelle HealthKit-opptak. Svært sjeldent
krasj rett etter at Watch har lagret i HealthKit, men før Watch
får opprettet terminalkvitteringen, skal fremdeles holdes
fail-closed inntil HealthKit-historikken er verifisert. Det er
ikke trygt å erklære en slik oppstart mislykket eller starte den
på nytt automatisk.

### Fase 4 – terminale fjernkommandoer er skrivebeskyttet (19.11.2026)

- iPhone sin Supabase-oppdatering for både `completed_at` og `failed_at`
  filtrerer nå på **begge** tomme terminalfelt. En forsinket feilcallback
  kan ikke overskrive en fullført start; en forsinket suksesscallback kan
  ikke overskrive en feilet kommando. Ved null oppdaterte rader beholdes
  eksisterende lokal suksessjournal inntil serverstatus er verifisert.
- Migrasjonen `20261119161500_workout_relay_terminal_state_immutability.sql`
  legger samme invariant i PostgreSQL: immutable bruker/request/payload,
  uforanderlig claim-eier etter claim, og terminalstatus som ikke kan
  omskrives. Den endrer ikke eksisterende historikk, HealthKit-opptak eller
  gamle kommandorader.
- XCTest dekker den terminale overgangsregelen. Migrasjonen må deployes og
  testes mot reell Supabase før fase 4 godkjennes; kode i GitHub alene
  betyr **ikke** at databasen er migrert.
- Resterende aksept: samme-commit iOS/iPad/watchOS bygg, XCTest,
  backend-/kompatibilitetstester og fysisk treenhetstest med HealthKit.

### Fase 5 – felles sannhetskilde for Audio Coach-avspilling (19.11.2026)

- Styrkens `StrengthAudioCoachSpeaker` beholdes som spesialisert
  sett-/hvileoppleser, men bruker samme felles hendelsesjournal og
  prioritetskø som løp, gåing og Watch. Ingen ny coachmotor, separate
  treningsopptak eller alternativ lydstemme innføres.
- `MirroredWorkoutAudioCoach`, `IPhoneWorkoutStore` og
  `WatchWorkoutManager` registrerer nå «spill siste melding» **først
  ved faktisk lydstart** (`AVSpeechSynthesizer.didStart` eller
  Azure sin `onStarted`), aldri bare ved bestilt syntese eller
  `speak(utterance)`. Dersom AVFoundation mister `didStart`,
  teller en vellykket `didFinish` også som bekreftet lyd.
  `didCancel` gir verken hendelseskvittering eller replay-minne.
- Mirrored Audio Coach sin tekstlige repetisjonssperre har nå
  separate `canAccept` (sjekk uten sideeffekt) og `didSpeak`
  (bekreftelse ved faktisk lydstart). Avbrutt Azure-oppslag skal
  ikke konsumere neste lovlige forsøk på samme coach-melding.
- Asynkrone lydmeldinger beskyttes med en avspillingsgenerasjon.
  En forsinket Azure-/AVSpeech-callback fra tidligere avbrutt lyd
  kan ikke oppdatere talekvittering eller «siste melding» for en
  nyere økt.
- Den felles `ATHLTHCoachCueQueue` forkaster målings-/intervall-/
  rute-/Ghost-/styrkesett-/hvilebeskjeder ved pause, gamle «start»/
  «pause»-meldinger etter gjenopptak og alle ventende meldinger ved
  fullføring. Samme policy brukes i speilet løp/gå, iPhone-løp/gå og
  Watch-økter. Eksisterende haptikk, HealthKit-opptak og
  tidsstyrte styrkesett påvirkes ikke.
- Nye regresjonstester kontrollerer at et tale-*forsøk* ikke
  utløser repetisjonssperren, at en bekreftet avspilling gjør det,
  at stillestående/forsinkede køhendelser fjernes ved pause,
  resume og øktslutt, og at neste økt får tom kø.

**Gjenstående fase-5-akseptanse:** Samme-commit grønn iOS/watchOS
build og målrettet XCTest. På fysisk iPhone + Watch må norsk/engelsk
stemmevalg, gjensidig talerett, AirPods/Bluetooth, Spotify-dukking
og musikkgjenopptakelse, nedtelling og Azure-fallback testes.
Audio Coach må heller ikke repetere en mottatt Watch-kvittering
eller snakke etter en avbrutt økt. Fase 5 kan ikke merkes
release-godkjent før dette er bekreftet.

### Fase 5 – fullføring av talerett, nedtelling og musikk (19.11.2026)

**Sammenhengende fase-5-kodeleveranse (ikke fysisk godkjent):**

- iPhone- og Watch-talerett er fortsatt basert på den eksisterende,
  kortvarige HealthKit-mirror-leien. En AI-samtale på iPhone opphever
  nå telefonens ordinære coach-lease umiddelbart, og nye tilbud/
  kvitteringer avvises mens AI-samtalen er aktiv. Status-/replay-UI
  krever både gyldig økt, riktig lyd-eier og ikke-aktiv AI-dialog.
- `MirroredWorkoutAudioCoach.suspendForWatchFallback` ugyldiggjør nå
  også avspillingsgenerasjon, ventende systemstemme og replay-minne,
  slik at en sen AVFoundation-/Azure-callback ikke kan erklære en
  melding opplest etter at Watch har overtatt. Det samme gjelder når
  en eksakt nedtelling overtar en vanlig stemmebeskjed.
- `onFinished` fra Azure er nå generasjonskontrollert både for
  speilet løp/gå, lokal iPhone-løp/gå og styrke. Et sent svar fra
  en gammel stemme kan ikke frigjøre en ny talers prioritet eller
  starte neste beskjed etter pause, stopp eller eierskifte.
- Watch sin sekundnøyaktige nedtelling sjekker nå sin absolutte
  sluttfrist **igjen etter** asynkron Bluetooth-/audio-route-
  aktivering. Et gammelt tall må droppes selv om lydruten først blir
  klar etter den aktuelle sekundgrensen. iPhone avviser tilsvarende
  gamle callbacks ved direkte kritisk nedtelling.
- Music/Spotify på iPhone beholdes under iOS sitt
  `AVAudioSession`-eierskap. Etter coach-stemmen bruker eksisterende
  `notifyOthersOnDeactivation` musikkens originale app som eier;
  ATHLTH starter ikke andre apper med en kunstig play-kommando.
  En route-change forårsaket av ATHLTHs **egen** kategoriendring
  starter nå ikke ny deaktivering i en løkke. Ekte AirPods-
  tilkobling/frakobling tillater fortsatt gjenopprettingsforsøk.
- Felles `ATHLTHCoachCueQueue` fjerner fortsatt foreldede
  intervall-, rute-, puls- og styrke-hvilebeskjeder ved
  pause, gjenopptakelse og øktslutt. Talerett,
  lyd-/hendelseskvittering og faktisk HealthKit-opptak holdes adskilt.
- Nye tester omfatter deadline-overskridelse under
  Bluetooth-aktivering, rutekategori-loop mot fysisk
  tilkobling, og tidligere tester dekker pause/resume,
  bekreftet avspilling og stale talekvitteringer.

**Release-akseptanse som ennå ikke er bekreftet:**

1. Samme commit må bestå iOS + watchOS + iPad-bygg,
   `ATHLTH Train and Hybrid Engine XCTest`, backend og
   iPhone-kompatibilitet. Kansellerte bygg er ikke grønne bygg.
2. Fysisk iPhone/Watch/AirPods: bytte talerett under aktivt drag,
   midt i en lang melding, ved avslutning, ved telefonlås,
   ved skjerm- og Bluetooth-brudd, og etter nettverksretur.
3. Offline Azure-fallback skal bruke lokal stemme uten å stoppe
   HealthKit, haptikk eller intervallmotoren, uten dobbel tale.
4. Spotify-spilleliste i faktisk avspilling: duck/mute etter
   brukerinnstilling, resume etter coach, etter to samtidige
   meldinger og etter AirPods-ruteendring. iOS eier musikk;
   vi kan ikke bevise faktisk Spotify-resume gjennom enhetstester
   som ikke er kjørt.
5. Løp, gåing og styrke med norske/engelske stemmer;
   kritiske rute-/pulsvarsler forblir høyt prioritert og
   nøyaktige nedtellinger må ikke snakke etter deadline.

**Status:** Den planlagte fase-5-implementeringen er lagt
inn i release-grenen, men fase 5 kan ikke kalles verifisert
eller release-godkjent før grønn CI og fysiske lydtester.
Ingen TestFlight-opplasting uten uttrykkelig godkjenning.

### Fase 6 – felles Live Activity, widget og Dynamic Island (19.11.2026)

**Samlet kodeleveranse på `release/v2.2.5`:**

- Alle overflatene leser fortsatt den eksisterende, autoritative
  `WatchWorkoutLiveSnapshot`-projeksjonen. `ATHLTHSurfaceRuntimeObserver`
  binder nå oppdateringer fra starten/slutten av iPhone-løp/gåing,
  intervalloverganger, innendørs økter uten GPS-punkter, endret styrkesett
  og hvile til **samme oppdateringsvei** for App Group-widgets og ActivityKit.
  Ingen ny HealthKit-skriver eller separat øktlogg er introdusert.
- iPhone-eide styrkeøkter projiseres direkte fra det eksisterende
  `StrengthWorkoutStore.activeWorkout` og `activeSessionState`:
  stabil økt-ID, øktstart, korrekt aktiv/pauset klokke, øvelsesnavn, sett,
  registrert belastning, hvilefrist og tidsstyrt sett. Watch-eide økter
  får fortsatt sensordata fra Watch og settdetaljer fra riktig styrkelogg.
  Slik får også lokal styrke samme Live Activity/Widget uten dobbelt opptak.
- Ny `ATHLTHSurfaceWorkoutOrdering` bruker øktidentitet og
  `capturedAt` som monotont vannmerke. Forsinkede pakker kan ikke
  overskrive nyere widget-data, eldre økt kan ikke erstatte en senere
  økt, og en kontoavgrenset **terminalmarkør** hindrer at en avsluttet
  økt vises som aktiv igjen – også etter omstart av iPhone-appen.
  Eldre App Group-snapshots dekodes uten terminalfelt.
- En iPad får bare oppdatere sin godkjente **lesevisning**. På iPhone
  kan ikke en remote widget-pakke overstyre det lokale opptaket.
  iPad kan reetablere sin widget etter app-omstart og fjerne gamle
  fjernvisninger uten å skrive til HealthKit.
- `ATHLTHLiveActivityDisplayPolicy.runningTransitionKey` markerer
  fase-/drag-/pausebytter som umiddelbare ActivityKit-oppdateringer.
  Måleverdier og sekundvis tidsendring ligger **ikke** i nøkkelen;
  native systemtimere fortsetter å telle mens sensortelemetri
  er begrenset. Styrkesett/øvelse/hvilefrist oppdaterer direkte.
- ActivityKit bruker kildens tidsstempel som `staleDate`, ikke
  tidspunktet når en forsinket telefonpakke endelig mottas.
  Gamle aktive pakker kan ikke nyopprette en Live Activity, mens en
  forsinket terminalkvittering fortsatt kan avslutte riktig økt.
  Asynkron ActivityKit-nedstenging stoppes ved nyere sync-revisjon.
- WidgetExtension skjuler også ved lasting et aktivt cache-element
  som allerede har terminalmarkør, viser korrekt pauset status og
  unngår ugyldig nedtellingsintervall når hvilefristen er utløpt.
  Widgets for iPhone/iPad/låseskjerm deler eksisterende klokkegrunnlag.

**Lagt til regresjonstester for:** same-session klokkevannmerke,
bytte av sport og ny økt, stoppmarkør og app-omstart, gamle JSON-data,
framtidige/ugyldige tidspunkt, drag-/pauseovergang, langt forsinket
Watch-snapshot og lokal iPhone-styrke etter avsluttet Watch-økt.

**Ikke godkjent for distribusjon:** Brukeren har utsatt fysisk testing.
Siste-commit iOS/widget/watchOS-build, relevante XCTest-suiter og
fysisk kontroll av låseskjerm/Dynamic Island, skjermlås, fem minutters
tredemølle uten GPS, gjenoppkobling og iPad-samtykke gjenstår.
Ingen TestFlight-opplasting. Fase 6 er implementert i kildekode,
men ikke release-/fysisk godkjent.


### Fase 7 – varig fullføringsjournal for løp/gå og styrke (19.11.2026)

- `PhoneWorkoutCompletionJournal` og `StrengthWorkoutCompletionJournal` avviser nå resultater hvor sluttid er før starttid. Journalene kan ikke lenger erstattes av en eldre, forsinket fullføringscallback etter en nyere økt. Eksisterende account-scoped filformat, HealthKit-opptakseier, workout-ID og historikk beholdes uendret; ingen datamigrasjon.
- Leseveien ignorerer også ugyldige tidsintervaller fra gamle/ødelagte journalfiler. Eldre gyldige filer dekodes som før.
- `ATHLTHPhoneCompletionJournalTests` tester kronologisk monotoni, ugyldig sluttid og isolasjon mellom kontoer. Den målrettede hybrid-XCTest-workflowen er oppdatert for å kjøre disse ved endring av journalene.
- Dette er en avgrenset fase-7-hardening, **ikke** godkjenning av HealthKit/resultater/historikk. Gjenstår: samme-commit bygg/XCTest, styrkejournalens integrasjonsregresjon, reell HealthKit-UUID-korrelasjon, gjenoppretting etter prosesskrasj, og fysisk test av løp/gå/styrke med Watch og iPhone.

### Fase 7 – HealthKit-identitet ved forsinkede styrkeresultater (19.11.2026)

- `StrengthWorkoutStore.attachFinishedWorkoutHealthKitUUID` avviser nå at samme
  HealthKit-UUID allerede er knyttet til en annen ferdig styrkeøkt i den
  autoritative kontohistorikken. Tidligere idempotent kvittering for den
  *samme* økten forblir tillatt.
- `attachFinishedWatchMetrics` avviser tilsvarende gjenbruk av HealthKit-UUID
  på tvers av økter, og avviser tom eller motstridende UUID når en fullført
  Watch-økt allerede har en koblet HealthKit-UUID. Dermed kan ikke forsinkede
  pakker fjerne opptaksidentiteten eller få en nyere økt til å overta den.
- Utvidede `StrengthWorkoutCompletionRecoveryTests` dekker ugyldig/eldre
  fullføringskvittering, kontoisolasjon, manglende Watch-UUID og gjenbruk av
  HealthKit-UUID mellom ferdige styrkeøkter.
- Dette er **lokal historikk-/evidenssikring**, ikke bevis for at HealthKit
  fysisk bare lagret én workout, og ikke en komplett PR-/segmentmotor.
  Samme-commit iOS/iPad/watchOS-build, XCTest/CI, reelle opptak og
  gjenoppretting på fysiske enheter er fortsatt nødvendig. Ingen TestFlight.

### Fase 7 – kontosynkronisert styrkehistorikk (19.11.2026)

- `StrengthWorkoutStore.mergeAccountSyncedWorkouts` avviser nå eksterne
  historikkposter med sluttid før starttid og poster som ville gitt samme
  HealthKit-UUID to ulike styrkeøkt-ID-er. Opprinnelige lokale poster
  har prioritet; gyldige distinkte økter importeres som før.
- En målrettet regresjonstest bruker to ulike trenings-ID-er med
  samme HealthKit-UUID for å kontrollere at den dupliserte posten
  ikke importeres, og sjekker ugyldig tidsintervall.
- Dette beskytter styrkekontohistorikken mot doble HealthKit-referanser,
  men beviser **ikke** fysisk HealthKit-idempotens på iPhone/Watch.
  Resultat-/PR-aggregasjon for alle treningsformer og release-kontroll
  gjenstår. Ingen TestFlight-opplasting.

### Fase 7 – stabil identitet ved lik avslutningstid (19.11.2026)

- Både `PhoneWorkoutCompletionJournal` og
  `StrengthWorkoutCompletionJournal` beholder den eksisterende varige
  kvitteringen når en annen økt ankommer med nøyaktig samme sluttid.
  Oppdateringer som gjelder samme økt-ID ved samme sluttid er fortsatt
  tillatt. Eldre sluttider avvises som før.
- Utvidede regresjonstester dekker likt sluttidspunkt med ulike økt-ID-er
  for både løp/gå og styrke. Dette er identitetsbeskyttelse i den
  eksisterende journalen, ikke en ny database eller opptaksstrøm.
- Verifisering av fase 7 er fortsatt åpen: full iOS/iPad/watchOS-bygg og
  målrettet XCTest på én og samme commit, fysisk HealthKit-korrelasjon,
  gjenoppretting etter krasj og fullstendig segment-/PR-regnskap.

### Fase 7 – resultatprojeksjon, korrekt PR-historikk og universell deduplisering (19.11.2026)

- `StrengthWorkoutResultBreakdown` er en **ren, ikke-lagret** visning av
  den eksisterende `StrengthWorkoutLog`. Sammendraget bruker samme
  autoritative øktklokke som live-motoren, inkludert pågående hvile som
  ennå ikke er skrevet til et sett. Først når økten er fullført kan en
  gyldig HealthKit-sluttvarighet få prioritet.
- Aktiv tid = total økttid minus faktisk registrert hvile, klamret til
  intervallet 0...total tid. Ugyldige/negative hviletall og ikke-fullførte
  sett får ikke påvirke hvile- og repetisjonssammendraget. Gjenopprettet
  iPhone-dødtid er allerede ekskludert i den autoritative klokken.
- Segmentprojeksjonen bevarer øvelse-ID, antall fullførte/hoppede sett,
  reps, volum og registrert settid. Hybridkardio skiller mellom
  **Watch-målt distanse**, **registrert distanse** og **estimert
  tredemølledistanse**; verdiene blir ikke slått sammen og kalt
  sensormåling. Det samme resultatkortet viser segmentene uten å lage
  en ekstra økt eller et nytt HealthKit-opptak.
- `StrengthWorkoutStore.workoutPersonalRecords` sammenligner nå en
  historisk økt med **tidligere** fullførte økter, ikke treningsøkter
  som ble gjennomført etter den aktuelle økten. Den første økten
  forblir referansegrunnlag selv etter senere trening.
- `ATHLTHRecordedWorkoutIndex.unlinkedKeys` grupperer lokale
  øktsnapshots per eksakt lokal ID før HealthKit-deduplisering. En
  tidlig post uten HealthKit-UUID kan ikke føre til at den samme økten
  telles om igjen når en nyere kopi får HealthKit-kobling.
- Testdekningen er utvidet for aktive pauser, gyldig/endelig HealthKit-
  varighet, utelatte sett, historisk PR-sammenligning, hybrid
  distanseproveniens og sen HealthKit-backfill. CI-workflowens
  filfilter inkluderer nå også styrkens gjenopprettingstester.

**Verifikasjonsstatus:** Kode og testtilfeller er lagt inn i
`release/v2.2.5`, men det foreligger ingen bekreftet grønn
samme-commit XCTest-/iOS-/iPad-/watchOS-kjøring i denne gjennomgangen.
Ingen fysisk HealthKit-kontroll eller TestFlight-opplasting er utført.
Full gjennomgang av alle eksterne sportsimporter, fysisk Watch-korrelasjon
og fase-8 regresjon gjenstår. Ikke marker fase 7 som release-godkjent.

### Fase 7 – registrert iPhone-løp/gå resultat (19.11.2026)

- `ATHLTHPhoneWorkoutResultBreakdown` gir én skrivefri projeksjon av
  autoritativ `PhoneWorkout`: aktiv økttid, veggklokketid, pausert/inaktiv
  tid, total distanse og deløkter. Eldre økter uten deløkter vises som før.
- Deløktlisten filtrerer ugyldige intervaller, velger den mest fullstendige
  av dupliserte registreringer per faktisk stegindeks, og bevarer kildebevis:
  oppgitte/estimerte mølledistanser blir ikke omtalt som sensormålinger.
  Den summerer aldri deløktdistanser på toppen av totaldistanse.
- iPhone-historikkortet bruker samme projeksjon og viser inaktiv/pause-tid
  separat fra faktisk aktiv tid. Regresjonstester dekker eldre/frie økter,
  pauseintervall, forsinket duplikatsteg og mølleproveniens.
- Ingen ekstra historikkpersistens, ingen ny HealthKit writer. Fase 7
  forblir uverifisert inntil samme-commit iOS/iPad/watchOS/CI og fysisk test.

### Fase 8 – lange økter og statiske ferdigresultater (19.11.2026)

- Ferdige styrkeøkters resultatkort bruker ikke lenger en sekundvis
  `TimelineView`. Den samme beregningen vises statisk fra lagret sluttid,
  mens pågående styrkeøkt fremdeles bruker den felles datobaserte klokken.
  Reduserer unødvendig UI-arbeid ved historikk og iPad-sammendrag.
- Nye regresjonstester dekker en 12-timers styrkeøkt med 10 timer
  gjenopprettet inaktivitet, gjentatt krasj-rekonstruksjon uten dobbel
  fratrekk, timed set med 12 timers overtid og pause/fortsett etter
  telefonlås. Ingen ny lagringsmodell eller treningsopptak er introdusert.
- Ytelses- og tidsforbedringene er ikke fysisk eller CI-verifisert før
  samme-commit iOS/iPad/watchOS-bygg, XCTest og målte tester er grønne.

### Fase 8 – Watch terminal-state and stale mirror identity (19.11.2026)

- `WorkoutMirroringStore.reconcileInactiveWatchActivity` treats an inactive
  Watch status as **ending**, not **completed**. The correlated final Watch
  result is the only path to the completed mirror state. The matching Live
  Activity is still dismissed immediately; no extra HealthKit recording or
  synthetic completion is created by the inactive status.
- `ATHLTHWorkoutMirrorContinuity.acceptsLiveSnapshot` refuses later
  strength snapshots missing or contradicting an already-established
  strength workout ID, and refuses later live updates omitting a previously
  established Watch start timestamp. The legacy pre-start/preparing path
  remains available when no start was known yet.
- Targeted XCTest cases cover inactive-to-ending status for running and
  strength, delayed correlated completion, missing stable strength ID,
  missing start timestamp and legacy pre-start transition.
- This is code hardening, not proof of real-device HealthKit consistency.
  Require same-commit iOS/iPad/watchOS/XCTest and physical handoff/finish
  tests before release or TestFlight.

### Fase 8 – løpehistorikk og HealthKit-korrelasjon (19.11.2026)

- `ATHLTHRunningPerformanceHistory.match` grupperer dupliserte snapshot
  etter lokal resultat-ID før matching, og foretrekker nyere kopier med
  eksplisitt HealthKit-UUID fremfor samme eldre lokale post uten UUID.
  Motstridende UUID-er for samme ID avvises; to ulike lokale poster med
  identisk HealthKit-UUID avvises som tvetydige.
- Omtrentlig match på sluttid/varighet er nå *bare* tillatt for eldre
  resultater **uten** eksplisitt HealthKit-identitet. En annen lagret
  HealthKit-UUID kan aldri forveksles med den etterspurte registreringen,
  selv om varighet og sluttid er nesten identisk.
- Watch-opptak med ikke-endelig eller negativ sluttid, ugyldig varighet
  eller ugyldig registrert minuttbevis oppretter ikke resultater i
  progresjonshistorikken.
- Utvidede `ATHLTHCompletedRunningPerformanceTests` kjøres eksplisitt
  i hybrid-XCTest-workflowen og dekker eksakt ID, sen HealthKit-backfill,
  entydig gammel registrering, motstridende ID og tvetydig kobling.
- Krever fortsatt vellykket samme-commit CI/Watch/iPad og fysisk HealthKit-
  validering før endelig fasegodkjenning. Ingen TestFlight-opplasting.

### Fase 4 – streng kommandokorrelasjon og kontobytte (19.11.2026)

- iPad-kommandokøen krever nå at den innebygde `clientRequestID` er identisk
  med den uforanderlige serververdien. Gamle kommandoer uten token kan ikke
  starte HealthKit; de avvises fremfor å bli utført uten mulighet for sikker
  rekonsiliering etter krasj. Eksisterende treningshistorikk påvirkes ikke.
- Mottak av nettverkssvar etter kontobytte oppdaterer ikke lenger ny brukers
  sendestatus eller feilmelding. Kommandoen som allerede ble sendt, tilhører
  fremdeles den opprinnelige kontoen; ingen automatisk overføring skjer.
- Krav om endelig utløpstid avviser korrupte ikke-endelige tidsverdier.
  XCTest er lagt til for manglende/feil request-ID og ugyldig utløpstid.
- Dette er ikke en godkjent fase 4. Full startveidekning, Watch-avklaring,
  iPad-samtykke, servermigrasjoner og fysisk iPhone/iPad/Watch-test må
  fremdeles bekreftes på samme commit. Ingen TestFlight.

### Fase 8 – HealthKit-ID i personlige rekorder på tvers av enheter (19.11.2026)

- `ATHLTHRunningPerformanceHistory.reconciledRecord` beskytter
  `savePhone`, `saveWatch` og `backfillPhoneHistory` mot ulike lokale
  progresjons-ID-er for samme HealthKit-UUID. Eksisterende UUID kan
  ikke overskrives eller mistes ved forsinket Watch/iPhone-pakke.
- Sen gyldig HealthKit-ID for samme opprinnelig ukoblede økt tillates.
  Regresjonstester dekker identitetskollisjon, sen backfill og ugyldig
  Watch-sluttid/varighet. Ingen ny database eller treningsopptak.
- Same-commit CI og fysisk iPhone/Watch HealthKit-verifisering gjenstår.

### Fase 8 – HealthKit eksport etter gjenoppretting og kontobytte (19.11.2026)

- `IPhoneWorkoutStore.retryHealthSave` slår nå opp økten på nytt i
  autoritativ, kontoavgrenset `phoneHistory` før forsøket starter. En
  gammel visningssnapshot fra en annen konto, en slettet økt, en aktiv
  eller ugyldig økt, eller en snapshot med avvikende start/slutt kan
  ikke eksporteres til Apple Health.
- `saveToHealth` validerer den eksakte eksisterende økten og kontoen
  før HK-kall, etter asynkron HK-oppslag og før lokal kobling av HK-ID.
  En annen lagret telefonøkt får ikke overta samme HealthKit-UUID.
- Tester dekker gyldig fullført økt, manglende lokal historikk,
  kontobytte, slettet konto, feil sluttid, ugyldig intervalldata og
  endret lokal økt-ID. Dette er en sikkerhetsgrense på lokal eksport,
  ikke en fysisk test av HealthKit eller garanti mot kontobytte mens
  selve HealthKit-operasjonen pågår.

### Fase 8 – immutable HealthKit-kobling (19.11.2026)

- Eksisterende iPhone-løp/gå-resultater med lagret HealthKit-UUID kan ikke
  endres til en ny HealthKit-UUID ved forsinket retry. Hvis historikken
  allerede har en UUID, men det eksakte HealthKit-oppslaget ikke finner
  opptaket, stoppes eksporten i stedet for å lage et nytt opptak.
- En idempotent gjentatt kvittering for samme HealthKit-UUID aksepteres.
  To forskjellige lokale treninger får ikke lov å ta samme UUID.
  `ATHLTHPhoneHealthExportPolicy.canLinkHealthKitWorkout` er testbar uten
  faktisk helseautorisasjon; fysiske telefon-/Watch-tester må fortsatt kjøres.

### Fase 8 – bred musikk/coach/legacy-testpakke og fjernet død kode (19.11.2026)

- Hybrid-XCTest får nå 12 eksisterende regresjonsuiter for
  Spotify-oppstart, sporbytte, valgt spilleliste, Audio Coach-lyd-/pauseregler,
  triggere og tempo/PR, gamle treningsplanblokker, strukturert planbibliotek og
  utkastgjenoppretting. Filer under `ATHLTH/Music` og relevante Spotify-editorer
  utløser også den målrettede testpakken.
- Bekreftet ubrukt `treadmillAveragePace` i live-løpevisning og ubrukt
  `completedSets` i sosial historikkmodell er fjernet. Ingen persistensfelt,
  overføring, layout-kontrakt eller HealthKit writer er endret.
- En bestått backend-jobb er ikke nok for release: iPhone/iPad,
  watchOS, simulert gjenoppretting og fysisk HealthKit/Spotify-samspill
  må kontrolleres på **samme commit** før fase 8 er godkjent.

### Fase 8 – konflikt i historikkidentitet og uavhengig iPad-smoketest (19.11.2026)

- `ATHLTHRecordedWorkoutIndex` avviser nå en lokal økt når dens egne
  snapshots har **to forskjellige HealthKit-UUID-er**, også før noen av
  dem finnes i den importerte HealthKit-listen. Tvetydig historie
  regnes ikke som et verifisert resultat og forurenser ikke andre
  økters UUID-deduplisering.
- To nye regresjonstester kontrollerer både konflikt uten HealthKit-
  import og at uavhengige gyldige økter fortsatt telles korrekt.
- `.github/workflows/ipad-smoke.yml` er aktivert på `release/v2.2.5`.
  Egen iPad-bygg/launch-smoketest kjører dermed uavhengig av full
  XCTest før de to sluttkontrollene for 11-/13-tommers iPad i
  `build.yml`. Ingen TestFlight eller ekstra HealthKit-opptak.
- Grønn GitHub-simulator betyr fortsatt ikke bekreftet ekte
  iPad/Watch-tilgang, HealthKit-opptak eller universell GPS+styrke.

### Fase 8 – fail-closed hybridopptak ved foreldet plan-snapshot (19.11.2026)

- `StrengthWorkoutStore.startPlannedHybrid` validerer den opprinnelige
  `PlannedSession` på nytt **før** ny styrke-/Watch-økt kan startes.
  Lengde og motorrekkefølge i callerens `validatedParts` må fortsatt
  stemme med kanonisk plan. Eldre/endrede deløktkopier skrives aldri
  direkte til den levende loggen: kun ferske kanoniske deler brukes.
- Regresjonstester kontrollerer foreldet antall deler, ugyldig endret
  motorrekkefølge og et forsinket deløktobjekt uten løpeblokker. Ingen
  ekstra HealthKit-opptak eller egen hybridresultatlogg.
- Fysisk iPhone+Watch-løping med GPS+styrke er fortsatt unsupported;
  dette hardener eksisterende tidsstyrte **innendørs** hybridøkter.

### Fase 8 – Watch-resultat ved delvis overførte løpeintervaller (19.11.2026)

- `ATHLTHCompletedRunningPerformance(watch:)` godtar fremdeles gyldige
  sensormålte minuttresultater fra en ekte avsluttet Watch-økt selv om
  hele intervallplanen ikke er fullført eller overført.
- En slik delvis overføring kan **ikke** produsere komplette per-drag-
  resultater eller personlige rekorder utledet fra ufullstendige
  intervaller. Registrerte deløkter beholdes bare når den komplette,
  sammenhengende strukturen er verifisert.
- Ugyldige minuttprøver (ikke-endelige tidspunkt eller distanse,
  negativ indeks/tid) filtreres før treningshistorikken lagres.
  Nye regresjonstester dekker delvis Watch-overføring, gyldig
  minuttbevis og ugyldige prøver.

### Fase 8 – kalenderstart, Watch-asynkronitet og bekreftet øktopptak (19.11.2026)

- Kalenderens styrke- og innendørs hybridstart bruker nå samme
  `ATHLTHWorkoutRecordingArbiter.reserveLaunch` før asynkront Watch-
  HealthKit-kall som øvrige startmotorer. Reservasjonen beholdes helt
  frem til lokal øktidentitet er verifisert; en parallell Run/Walk/Strength
  kan ikke starte under ventetiden.
- Etter Watch-svar kontrolleres samme innloggede bruker og kontoens
  styrkelogg før en styrke- eller hybridøkt opprettes lokalt.
- `StrengthWorkoutStore.matchesStartedPlannedWorkout` verifiserer
  **planlagt økt-ID, aktiv status, opptaksenhet og Watch-korrelasjon**.
  Hjem/kalender kan ikke registrere startet trening bare fordi
  `StrengthWorkoutStore.start` (som returnerer `Void`) ble kalt.
  Den samme regelen gjelder direkte iPhone-start.
- Hvis Watch har bekreftet start, men iPhone ikke har et matchende
  checkpoint, får brukeren beskjed om å sjekke Watch. Appen starter
  **aldri automatisk en ny HealthKit-økt** for å skjule usikkerheten.
- Tester dekker faktisk bekreftet iPhone-/Watch-eier, feil plan-ID,
  feil Watch-session-ID og avvist konkurrerende start.
- Fullført CI og fysisk Watch-/iPad-korrelasjon kreves fortsatt.

### Fase 8 – tidsstyrt utendørs GPS + styrke på Watch (19.11.2026)

- `ATHLTHHybridWorkoutLaunchPlan.parts(for:allowOutdoorGPS:)` godtar
  eksplisitt tidsstyrte utendørs løpeblokker + styrke **kun når Watch
  eier opptaket**. Den krever `isIndoor == false` på løpeblokkene,
  ingen distansebaserte drag og ingen uoverført lagret rute. iPhone-only
  GPS-hybrid og tvetydige treningsmiljøer avvises.
- Watch starter ett `HKWorkoutSession` som `.crossTraining` med
  `.outdoor`; eksisterende Watch-styrkejournal og `StrengthWorkoutLog`
  eier alle delresultater. Ved Watch-gjenoppretting rutes denne
  HealthKit-typen tilbake til samme hybridkontroller.
- Den bakoverkompatible `StrengthWorkoutLog.isOutdoorHybrid` markerer
  den ene lagrede økten. Løpedeler merkes «Outdoor Running» i stedet
  for «Treadmill Running». Plan, Watch, sett og HealthKit beholder
  hver sin opprinnelige, korrelerte ID uten dupliserte opptak.
- Watch registrerer GPS-rutepunkter, fallbacksensor-distanse og
  GPS-pace bare i aktiv utendørs løpefase. Vanlige styrkesett,
  innendørs hybrid og alle inaktive løpefaser får ingen rute.
  `distanceWalkingRunning` blir aktivert for løpefasen gjennom
  eksisterende Watch-sensorlogikk.
- Apple Health tillater ikke separate løpe- og styrkeaktivitetskategorier
  i én vanlig cross-training-økt. Segmentene beholdes derfor i ATHLTH;
  ikke kall dette en native HealthKit multisportaktivitet.
- Nye tester dekker Watch-opptaksidentitet, korrekt utendørsmerking,
  JSON-kontinuitet, avvisning på iPhone, ugyldige distansemål og
  GPS-rute kun ved aktiv løpefase.
- **Koden er ikke en fysisk verifisert GPS/HealthKit-funksjon.**
  Samme-commit CI/iOS/iPad/watchOS og reelle Watch-sensorprøver er
  obligatoriske før release-godkjenning.

### Fase 8 – GPS-pause og fasegrenser for utendørs hybrid (19.11.2026)

- Ruteopptak i Watch-styrke-hybrid krever nå både `outdoor`, aktivt
  løpedrag, ingen hvile, ikke fullført øvelse og en `running` Watch-session.
  Pause, overgangen til styrke og siste fullførte drag kan ikke legge til
  GPS-punkter eller endre utendørs pace.
- Når HealthKit-sensorkilden bytter mellom løpe- og styrkefase nullstilles
  lokal GPS-forrige-punkt-basis slik at «hopp» over styrkesettet ikke blir
  registrert som en løpedistanse. Den autoritative akkumulerte målingen
  nullstilles **ikke**.
- Tester dekker paused/resting/completed og vanlig aktiv utendørsfase.
  Reelle GPS-prøver på Watch er fortsatt nødvendig før endelig godkjenning.

### Fase 8 – GPS-distansemål i Watch-eid hybrid (19.11.2026)

- Eksplisitt utendørs Watch-løpedrag kan nå velge **enten** 15–7200 sekunder
  **eller** 100–50 000 meter. Manglende eller ugyldig sensorbevis,
  samtidig tids-/distansemål og manuell møllefart avvises.
- Distansemålet lagres bakoverkompatibelt i original styrkeøkt,
  øktens setjournal og `WatchStrengthSetPlan`. Det er ikke en
  HealthKit-måling. Distanseprogresjon bruker bare akkumulerte **målte**
  Watch-distanser minus en lagret per-sett baseline.
- `ATHLTHHybridWatchDistanceAnchor` lagres i den eksisterende Watch
  krasj-recovery-checkpointen og omfatter workout-ID, exercise-/set-ID,
  distansebaselinje og aktiv HealthKit-øktklokke. Restart eller pause
  lager ikke ny treningsøkt eller nullstiller distansemålet fra start.
- Når faktisk mål nås under aktiv løping, sendes normal idempotent
  Watch-styrke-settkommando; varigheten beregnes fra HealthKits **aktive**
  klokke uten pause. Hvis distanse mangler, blir draget ikke auto-fullført.
- iPhone-kortet viser distansemål uten å finne på en 60-sekunders
  nedtelling og uten manuell møllefart for utendørs GPS-faser.
- Tester dekker mål, identitet, kryss-restart, ikke-endelig GPS,
  distansegrense, ugyldige mål og planens metadata.
- Fremdeles ikke fysisk Watch-/HealthKit-verifisert; iPhone-only GPS
  hybrid er separat og krever en iPhone-eid GPS-kilde før release.

### Fase 8 – én hybridstart fra iPad-relay, kalender og Train (19.11.2026)

- `WorkoutLaunchCoordinator.startStrength` validerer alle kombinerte
  planer **før** iPad-relay, sosial invitasjon eller Watch HealthKit-start.
  Gyldige planer bruker nå den samme kanoniske `startPlannedHybrid`
  i stedet for at en alternativ startsti starter ren styrke og mister
  løpeblokkene. Avviste blandingsplaner starter ingenting.
- Outdoor Watch-hybrid velger `.crossTraining` med `.outdoor`,
  mens vanlig styrke og tredemølle beholder innendørsaktivitet.
- `startPlannedHybrid` overfører også eksisterende Audio Coach/
  advanced config og `relayRequestID` til original logg. Dette
  oppretter **ikke** parallelt PhoneWorkout eller annet HK-opptak.
- Nye tester sikrer plan-ID, Watch-session, original relay-ID og
  alle løpeblokker i ett opptak. Samme-commit CI og fysisk enhetstest
  er fortsatt et obligatorisk release-godkjenningskrav.

### Fase 8 – korrekt Watch-presentasjon for GPS-distansemål (19.11.2026)

- Begge styrke-/hybridlivevisningene på Watch viser GPS-distansemålet i
  kilometer og når tilgjengelig **målt distanse siden aktivt drag startet**.
  De viser ikke lenger en redigerbar tids-Crown for distansebaserte drag.
- Fremdrift hentes fra den durable `ATHLTHHybridWatchDistanceAnchor`
  (workout+øvelse+sett), ikke den kumulative distansen i hele økten.
  Pausede og avsluttede drag viser ikke et falskt GPS-framdriftstall.
- Faktisk sensor-/HealthKit-validering må fortsatt gjennomføres på en
  fysisk Apple Watch før funksjonen kan erklæres ferdig.

### Fase 8 – korrupt Watch-checkpoint og automatisk GPS-pause (19.11.2026)

- Gjenopprettede distanseankre med negativ/ikke-endelig baseline,
  ugyldig tidsstempel eller ugyldig GPS-mål kan ikke vise fremdrift,
  gi fullføringssignal eller produsere settvarighet.
- Nye ankere krever gyldig øvelses-/settindeks og en aktiv løpefase.
  Bytte til en annen trening, stasjon eller øvelse gjenbruker aldri ankeret.
- GPS-lagring, pace, fremdrift og automatisk fullføring av
  distansedrag er sperret under automatisk pause. Automatisk
  distansefullføring krever utendørs Watch-eid styrkehybrid.
- Nye XCTest-regresjoner er lagt til. Fysiske Watch-/HealthKit-/GPS-
  tester og full samme-commit CI kreves fortsatt før release-godkjenning.
