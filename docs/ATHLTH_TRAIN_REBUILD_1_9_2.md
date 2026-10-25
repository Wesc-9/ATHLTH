# ATHLTH Train: godkjente beslutninger og gjenoppbygging

Arbeidsgrunnlag: samtaler 23.–25. oktober 2026. Aktiv utviklingsgren: \`main\`.
Denne oversikten er en samling av tilgjengelige godkjente beslutninger, ikke en ordrett eksport av samtlige tidligere samtaler eller bildene i dem.

## Ufravikelige prinsipper
- Premium, minimalistisk, konsistent ATHLTH-uttrykk: lys/off-white og champagne/gull. Ingen nye grønne eller blå dominerende Train-kort.
- Godkjent visuell retning for **I dag**: «Abstrakt dynamikk», asymmetrisk stor metallisk ATHLTH-skulptur til høyre, og et selvstendig, rolig tekstområde til venstre. Godkjent skulptur skal ikke endres. Første kodefase lar eksisterende hero-ressurs være urørt i påvente av eksakt visuell kilde, og bygger innholdet under den.
- Ikke kopier bilde-/muskelhero i flere kort. Eksisterende godkjent øvelses- og oppsummeringsdesign skal bevares.
- Apple Watch er essensiell; ingen ombygging må skade start, fortsettelse, registrering, synk eller HealthKit.
- Ingen TestFlight uten eksplisitt beskjed; fullførte økter/historikk må aldri omskrives av planredigering.
- Skill planlagt trening, faktisk gjennomført trening, manuelt registrerte verdier og estimater.

## Navigasjon
- Train har «I dag», «Plan» og inngang til «Fremgang». Bibliotek åpnes fra ikon øverst til høyre.
- Tilbakeknapp fra underliggende fremgangs-/detaljskjermer skal hete «Train».
- Pågående økt / Fortsett trening skal prioriteres over andre handlinger.
- Ved ny økt må eksisterende koordinatorer for iPhone / Apple Watch gjenbrukes, ikke dupliseres.

## «I dag» – godkjent innhold
- Tydelig én hovedøkt / neste økt: dato, navn, type, varighet og relevante deløkter.
- Se detaljer og trygg start (iPhone/Watch-valg i eksisterende startflyt). Flere økter per dag skal være synlige uten dupliserte primærkort.
- Quick Train: Løp, Gå, Styrke (og Egen når støttet). Vennerekke og tren-sammen må integreres i senere fase.
- Fremgang: Generelt, Styrke, Løping, med enkel inngang fra Train.
- Ikke vis dobbelt tidsbruk / øvelser / volum i kortene.
- Respekter aktiv plan, men tillat enkeltøkter uten aktiv plan.

## «Plan» – godkjent innhold
- Kompakt header for aktiv plan, trykk åpner «Mine planer» i egen fullskjerm.
- Maks én aktiv plan; fremtidige og tidligere planer bevares.
- «Mine planer»: aktiv, lagrede, utkast og arkiv som tydelige grupper. Kildedata for utkast må først avklares – ikke skap fiktiv utkaststatus.
- Ukevalg under header. Uke-/dagsoversikt har fullbredde rader, ikke små kalenderfliser. Flere økter per dag.
- Trykk på dag for å se planlagte økter, åpne detaljer og legge til.
- Uke-kopiering: forhåndsvisning, fyll tomme dager som standard, beskytt eksisterende/individuelt tilpassede dager; ingen stille overskriving.
- Valg om endring av én forekomst eller alle fremtidige ved gjentakende økt.
- Flytt / hopp over / gjenopprett med riktig historikk og planstatus.
- Enkeltøkter utenfor plan er en separat kalenderkilde; må ikke forveksles med planøkter.

## Øktbygger / felles motor – senere implementeringsfaser
- Én felles underliggende plan og økteditor, med Enkel / Avansert uten tap av detaljer.
- Vertikal tidslinje med utvidbare blokker og deløkter, mulighet til å åpne fullskjerm.
- Blokkrekkefølge: Løping, Gå, Sykling, Yoga, Meditasjon; Øvelse, Treningsøkt; Intervall, Supersett, Pause, Uttøying.
- Gruppe- og blokkeditor: oppvarming, hoveddel, nedjogg, pauser, måltempo/puls per drag, mål for styrke, øvelsesbilder, muskelkart, treningssted.
- Endre rekkefølge uten å miste loggede sett. Lagring av egne økter, kopiering til andre dager.
- «Planlegg resten» gjelder kun ufullført innhold, foreslå helt sett/drag på nytt, valgfri rest. Ingen dobbeltelling eller automatiske endringer av historikk.
- Ny deløkt i aktiv trening foreslås etter aktiv deløkt, kan legges sist, krever bekreftet start.
- Øvelsesbytte foreslår alle gjenstående sett, tilbyr kun neste sett; fullførte sett beholdes.
- Unngå å opprette separate/doble HealthKit-økter ved styrke → mølle og lignende overganger.

## Gjennomføring i faser
1. **Ny Train-visning:** I dag-hierarki, kompakt Quick Train, Plan-header, ukebytte og fullbredde dagtidslinje. Bevar faktisk øktstart. *(Påbegynt på main.)*
2. **Mine planer og planinteraksjoner:** enhetlig fullscreen aktiv/lagret/utkast/arkiv, trygg kopiering, flytting og håndtering av enkeltøkter.
3. **Felles økteditor:** én vertikal editor for alle blokktyper, Enkel/Avansert og fullskjerm-detaljer.
4. **Integrasjon med aktiv trening og Watch:** strukturerte kombinasjonsøkter, korrekt gjenoppretting og bekreftet motorovergang.
5. **Regresjon og kvalitet:** skjermtest iPhone/iPad, ulike tilstander (ingen plan, flere økter, offline, utkast, delvis gjennomført), oversettelse, VoiceOver og HealthKit. TestFlight først etter særskilt brukerbeskjed.

## Før godkjenning
- Nye skjermer må bygges uten Swift-feil og fungere med eksisterende plan.
- Ingen endring av fremmede faner, treningsmotorens målinger eller release-grenen.
- De opprinnelige illustrasjonene må kontrolleres visuelt mot godkjent design før UI regnes som endelig.

## Implementeringsstatus – 25. oktober 2026, fasevis
- **I dag:** ny datadrevet overflate brukes fra `ATHLTHTrainView`; planlagt hovedøkt, flere økter, Quick Train, hviledag og trygg øktstart er koblet til eksisterende koordinatorer. Godkjent skulpturell hero er fortsatt en egen visuell sluttkontroll.
- **Plan:** ny datadrevet ukeoversikt og fullbredde dagkort er i bruk, med åpne dager, lesbare øktblokker, enkeltøkter, kopier uke, flytt/hopp over og detaljvisning uten startknapp. Valgt uke og åpne dager huskes nå mellom fanevisninger via `SceneStorage`.
- **Fase 2, hurtigredigering:** styrkeøkter med enkle øvelseslister kan justere sett, reps eller settvarighet og pauser fra dagkortet. Endringer lagres kun ved bekreftelse. Eksisterende resultatdata, belastning, superset-/gruppeidentitet og øvrige øktdetaljer beholdes. Strukturerte blandingsøkter må fortsatt bruke full editor.
- **Oversikt:** ukens antall økter inkluderer nå separat planlagte enkeltøkter på samme dato.
- **Ikke ferdig:** egen ny blokkbasert felles økteditor med flyttbare grupper, alle treningsformer og avanserte per-drag-mål. Avtalt rulleposisjon ved retur er ennå ikke fullt implementert. Watch-kombinasjonsmotor krever fortsatt verifisering. Ingen TestFlight for disse `main`-endringene.

## Faste kontroller videre
- Ingen automatisk endring av fullførte/historiske økter.
- Hurtigredigering må kontrollere at øktforekomsten fortsatt er uendret og ikke er registrert fullført ved lagring.
- Uke- og dagvalg må bevares ved modaler, navigasjon og fanebytte; rulleposisjon trenger egen kontroll.
- Verifiser Swift-build, regresjonstester og fysisk layout før noe kan beskrives som ferdig.


## Fase 3 – blokkredigering på aktiv `main`, 25. oktober
- Den eksisterende økteditoren (`SessionEditorView`) har nå en redigerbar tidslinje for lagrede strukturerte blokker, i stedet for en liste som bare viser de fem første.
- En blokk kan åpnes for navne-/målredigering og flyttes opp eller ned. Pauser og notater kan legges til. Kopiering av blokkmetadata ved flytting og sletting er isolert i `ATHLTHWorkoutBlockEditing` og har regresjonstester.
- Øvelsesreferanser, belastning, distanser og mål videreføres når rekkefølgen endres; historiske prestasjoner berøres ikke.
- Øvrige aktivitetsformer, avansert per-drag-tempo/pulssone og flertrinns supersettmotor krever fortsatt den planlagte samlede editoren. Det er **ikke** innført fiktive blokktyper som dagens modell ikke støtter.
- Må kvalitetssikres med Swift-build, iPhone/iPad-visuell test og fokus på tastatur, redigering under planbytte og lagring av blandingsøkter. Ingen TestFlight er startet for disse main-endringene.
