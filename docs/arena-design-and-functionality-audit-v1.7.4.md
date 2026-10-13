# ATHLTH Arena · audit, visuelt system og kvalitetssikring

Gjennomgått mot `release/v1.7.4`. Denne filen beskriver den faktiske arkitekturen og
endringene i første designsprint. Den bekrefter ikke gjennomført fysisk iOS-/Watch-testing.

## Prinsipp: samme ATHLTH-opplevelse som Treningsplan

**Enkelt å starte, avansert når du trenger det.** Behold eksisterende ansvar:
- `ATHLTHArenaLightStyle.swift` er Arena sitt **sentrale designpunkt**. Paletten
  er synkronisert med `ATHLTHTrainPlanPremiumView.swift`: papirhvit/off-white,
  grafitttekst, varm gullaksent, dempede sekundærflater, serif-titler.
- Enkel/Avansert i Arena er kun presentasjon, ikke forskjellige lagrings-,
  resultat-, invitasjons- eller treningsmotorer. Valg huskes med `AppStorage`.
- Begge modusene viser delte konkurranser, utfordringer, Live-dueller og
  private utkast. Sesonger, snarveier og komplekse oppsett er i Avansert.
- Viktige beslutninger skal ha én tydelig CTA. Ingen automatisk invitasjon
  ved valg av mal eller opprettelse av lokalt utkast.
- Alle skjermbilder må tåle norsk/engelsk, stor tekst, VoiceOver og iPad.
  Bilder klippes innenfor sine tildelte rammer, aldri fri `scaledToFill`-overflyt.

## Nåværende domener og kodestrømmer

| Område | Eksisterende arkitektur | Verifikasjonsbehov |
|---|---|---|
| Enkelutfordring | `ChallengeCreationView`, separate challenges | Invitasjon godkjennes før økt teller, ingen overlapp med «Uken challenge» |
| Rute/distanse | `SavedRoutesView` og `ATHLTHArenaDistanceStarter` åpner Challenge | Rute fryses og kilometer valideres; faktisk GPS-bevis kreves for offisiell rangering |
| Konkurranseserie | `ATHLTHArenaCreateView` -> lokalt utkast -> `ATHLTHArenaCloudService.publish` | Manglende deltakere/runder/klubb blokkeres. Skille på lagre og sende |
| Regelavtale | `ATHLTHArenaNextAction`, `ATHLTHArenaRuleAgreementPresentation` | Alle inviterte må svare og aktive deltakere godkjenne før start |
| Resultat | `ATHLTHArenaScoringSection`, serverstyrt poeng og stemmer | Kun godkjent resultat gir poeng; status ved avslag, uenighet og utløpt frist |
| Live Ghost | Eget sanntidsrom, med Arena-rundekobling | Ingen dobbeltstart. Usikker klokke eller GPS må kreve kontroll |
| Lag | Server-frosne medlems- og lagoppstillinger | Antall, like lag, godkjente erstatninger, slettet medlems poeng |
| Stafett | `ATHLTHArenaRelayLeg` og `ATHLTHArenaRelayLegReport` | **Rapporterte** tider er ikke automatisk GPS-verifisert stafettveksling |
| Klubb/sesong | Separate sesonger og konkurranser via ArenaCloud | Administratortilgang, sesongkobling og arkiv; ingen nye poeng fra kun visning |
| Lokale utkast | `ATHLTHArenaDraftStorage` i kontospesifikt UserDefaults | Utkast er enhetslokale og kan gå tapt ved avinstallering |

## Funn som ikke bør løses med bare design

1. **Produktmodell:** Brukerne må forstå forskjellen mellom enkeltutfordring,
   serier, Live Ghost og redaksjonell «Uken challenge». De skal bruke et felles
   designspråk, men ikke samme poeng- eller godkjenningsregel.
2. **Distribuert tilstand:** OnlineSection, ScoringSection, Live Duels og Seasons
   laster fra forskjellige datakilder. En fremtidig «Neste handling»-oversikt
   bør ha en lesebasert aggregatmodell, ikke kopiere all tilstand til hver view.
3. **Bevis:** Tid, ruteavvik, distanse og HealthKit-økt kan gi motstridende
   signaler. Render kun verifiserte tider som sikre vinnere; manuell kontroll
   brukes ved manglende/ukorrekt dokumentasjon.
4. **Rettigheter:** RLS, administratorstatus og godkjenning må fortsatt
   avgjøres på serveren. Ingen ny designknapp gir i seg selv skriveadgang.
5. **Persistens:** Lokale utkast bør på sikt ha eksplisitt sikkerhetskopi/
   gjenoppretting når denne delen prioriteres; ingen automatisk sky-migrering
   er innført i denne designpakken.

## Endret i designpakken

- Ny editorial header på Arena-hjem med Enkel/Avansert, ett tydelig
  opprettelsesvalg og off-white/serif-design som Treningsplan.
- Enkel startkort med invitasjonsflyt, rutestarter og distansestarter.
- Eksisterende delt/aktiv konkurranse, utfordringer, Live Ghost, private utkast
  beholdes synlige i begge modi.
- Eksisterende avanserte snarveier, team/stafett, serieoppsett og klubb-sesonger
  beholdes under Avansert.
- `ATHLTHArenaLightStyle` er designets sentrale kilde; kort, border og
  bakgrunn henter samme varmtonede palett.
- Serieopprettelse, utkastvisning og online-konkurransedetalj får
  redaksjonell teksthierarki. Ingen server-RPC-er eller poengregler endret.

## QA / aksept

**Visuelt:** 320–430 pt bredde, iPad split view, stor skrift, VoiceOver,
norsk/engelsk, reduced motion. Bildet skal aldri overløpe kortet. Enkel
og Avansert skal være forståelige uten brukerinstruksjon.

**Funksjonelt:** Opprett standardutfordring, velg rute, egendefinert
distanse, styrke, serie og team/stafett. Kontroller at et lokalt utkast
ikke sender invitasjon. Test godta/avslå, regelgodkjenning, flytting til aktiv
konkurranse, validering av rute, godkjenning/avslag på resultat og poeng bare
etter vedtak. Test slettet konto, erstatning med nødvendig samtykke, arkiv,
reconnect, offline-retry og utilgjengelig Supabase. Enkel-modus må fortsatt
vise oppgaver som trenger respons.

**Teknisk:** Swift-syntaks, XcodeGen, iPhone/iPad/Watch kompilering,
regresjonstester, UI-kontroll og fysisk test i TestFlight først på uttrykkelig
forespørsel. Ikke godkjenn kun på grunnlag av kildekodegjennomgang.

## Videre anbefalt implementeringsrekkefølge

1. Et lesebasert «Hva krever handling»-panel på forsiden, basert på samlet
   datagrunnlag for invitasjoner, regelavtale og resultatstemme.
2. En felles visuelt orkestrert opprettelsesflyt for enkeltutfordring og
   serier, men fortsatt separate underliggende sikre motorer.
3. Samme designkomponenter for live-duell, resultatoversikt, sesong og
   klubb – og en konsekvent taksonomi for «Venter / Pågår / Må godkjennes».
4. Eget dokumentert bevisnivå for stafett, styrke og rute, med tydelig
   manuell kontroll når automatisk kvalitet ikke kan dokumenteres.
5. UI-snapshottester + E2E av varsler, multiløp, ghost, lag og iPad.
