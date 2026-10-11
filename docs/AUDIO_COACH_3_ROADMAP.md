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

**2B: Leveringssikkerhet og flere kategorier**

- [ ] Ekte felles prioritetskø, sammenslåing og utløp for alle talte Ghost-/rute-/styrke-/målsonehendelser.
- [ ] Kvittering for event-ID på tvers av iPhone/Watch, med korrekt at-most-once-forsøk ved overlevering.
- [ ] Tydelige regler for haptikk/voice-kombinasjon og lokalisering av alle treningsmeldinger.
- [ ] Regelstyrt, offline og uten nettanrop på live-kritisk bane.
- [ ] Kontroll av sensorers alder og kvalitet før målsone- og tempoanbefalinger.
- [ ] Minimal hendelsesdiagnostikk uten identifiserende eller følsomme treningsopplysninger.
- [ ] Fysisk test av AirPods/Spotify, bakgrunn, pause/fortsett og iPhone-til-/frakobling.

**Avgrensning:** 2A gir *lokal* duplikatkontroll for utvalgte typer, ikke global exactly-once-garanti på tvers av enheter. Markører inneholder kun type og intervall-/steg-ID, ikke selve talemeldingen eller brukerens helsehistorikk.

### 3. Oppdagbarhet og premiumdesign

- [ ] Synlig, kompakt coach-status i *alle* støttede øktstarter; ikke gjemt under «Avansert».
- [ ] Enkel / Standard / Avansert = **innholdsnivå**, uavhengig av talefrekvens.
- [ ] Separat talefrekvens og talestil (balansert, teknisk, motiverende, minimal).
- [ ] Premium ghost/off-white visning for konfigurering, live og Watch; ikke skjul viktige treningstall.
- [ ] Ettrykks lydpause, status nå, justering, forhåndslytt og valgt lydutgang.
- [ ] Globalt standardvalg, per økt override og tydelig når hvilke innstillinger gjelder.
- [ ] iPhone live er allerede introdusert på `release/v1.7.3`; utvid tilsvarende til styrke, strukturert plan og Watch uten regresjon.

### 4. Løping og treningsplaner

- [ ] Bevar fase-type (oppvarming/arbeid/hvile/steady/nedtrapping) i Watch-transfer i stedet for friteksttittel alene.
- [ ] Neste-drag-forhåndsvarsel, nedtelling, overganger, midtveisstatus og cool-down.
- [ ] Smart Pace Coach med glattet tempo, hysterese, grace window og faktisk målsone.
- [ ] Pulssoneinstruksjoner bare ved valide, ferske sensordata + aktivt mål.
- [ ] Innendørs tredemølle uten falsk GPS-rute; høydedata bare når støttet.
- [ ] Bruker skal kunne legge inn coach-mål i en planlagt økt og endre det underveis.
- [ ] Manuell «Gi meg status nå» iPhone + Watch, samt seneste beskjed.

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
