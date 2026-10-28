# ATHLTH Coach 2.0 – integrert styrkeintelligens

Kildereferanse: [GymCoach](https://github.com/gymcoach-app/gymcoach) (MIT, Copyright 2026 GymCoach contributors). ATHLTH bruker egen datamodell og egen coach, ikke en separat GymCoach-server eller database. Lokale treningsberegninger kan fungere uten nett, mens AI-chat og talesamtaler bruker eksterne leverandører.

## Implementert på release/v2.0.1

- Lokal, skrivebeskyttet analyse av fullførte styrkelogger siste åtte uker: arbeidssett, vekter, estimert 1RM, progresjon og forsiktig vurdering av stagnasjon. Manglende historikk er aldri bevis på inaktivitet.
- Analyse i eksisterende progresjonsvisning. Eksisterende mekanisme for godkjente planendringer, krav til to fullførte dokumenterte økter og sikkerhetsgrenser beholdes.
- AI-planbygger med begrenset strukturert treningskontekst, kun ved aktivert Coach-historikk.
- Vanlig ATHLTH Coach-chat kan lese samme treningskontekst kun etter bekreftelse for det enkelte helse-/treningsdatadeling-spørsmålet. Serveren avviser utlevering ved manglende samtykke og saniterer kildedata; samtaleloggen videreføres under tidligere personvernregler.
- Live AI-talesamtale har en ny, selvstendig og frivillig styrkehistorikk-bryter. Bare om brukeren aktiverer den, får talesamtalen et verktøy som kan returnere lokalt styrkesammendrag på forespørsel. Samtalen er tidsbegrenset. Ingen posisjon eller skadenotater inngår i dette verktøyet.
- 11 GymCoach-inspirerte, lokalt lagrede styrkeprogrammaler med **40 ulike økter** og **167 øvelsesoppføringer** er registrert i ATHLTH Planbibliotek og øktbibliotek. Hver økt beholder sett, repetisjoner, RIR, restitusjonstid og en tidslinje som ATHLTH kan utføre/redigere. A/B-programmene alternerer over tre økter per uke.
- Norsk oversettelse gjenbruker ATHLTHs etablerte øvelsesnavn og egne program-/økttekster der det finnes tilsvarende oversettelse. Kildedata forblir uendret, og det kan gjenstå redaksjonell kontroll av enkelte øvelsesnavn.

## Viktig begrensning for treningsprogrammer

GymCoach inneholder kildeprogrammer og beskrivelser av 5/3/1, nSuns m.fl., men **ikke maskinkjørbare, komplette numeriske vektbølger for disse programmene**. Vi importerer derfor redigerbare, repeterende åtteukersoppsett fra kildemalen med reelle sett/reps/pauser. Ingen treningsmaks, vekt eller senere progresjon fabrikkeres. Brukeren og/eller ATHLTH Coach må kalibrere progresjonen basert på faktisk registrert data og godkjenne endringer. Disse malene skal IKKE markedsføres som fulle automatiserte reproduksjoner av proprietære treningsprogrammer uten videre implementasjon og juridisk kvalitetskontroll.

## Personvern og migrasjon

- Ingen automatisk overføring av styrkelogger til AI uten aktuell brukerbeslutning. Skadedata har separat eksplisitt samtykke. Status- og historieforespørsler er skrivebeskyttet; AI endrer ikke historikk.
- Apple Watch, Apple Health, Zoned-programmer og alle eksisterende økter og planer bevares. Ingen sletting eller migrasjon av lagrede data.
- De eksisterende Coach-rutene beholdes til end-to-end iOS/Watch- og backend-tester samt rollback er godkjent. Implementasjonen er en samling i eksisterende Coach, ikke dobbel Coach.

## Sjekkliste før TestFlight / offentlig utrulling

1. Bekreft iOS-, iPad- og Apple Watch-bygg og backendregresjoner mot siste commit.
2. Test Coach-chat med og uten delingssamtykke, og stemme med historikk AV/PÅ.
3. Verifiser at styrkeøkter faktisk kan åpnes, redigeres og gjennomføres fra planen på iPhone/Watch.
4. Kontrollér alle norske øvelsesnavn og treningsinstruksjoner og rettigheter til tredjepartsprogramnavn/-innhold. MIT-programvarelisens er ikke automatisk kommersiell lisens for uavhengige treningsbøker og varemerker.
5. Full automatisering av prosentbølger og avansert deload er et eget videreutviklingssteg.
6. Ingen TestFlight-opplasting uten eksplisitt beskjed.
