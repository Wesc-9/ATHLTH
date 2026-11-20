# ATHLTH 2.2.6 – felles intervallklokke for Custom Quick

Denne endringen samler ren tidsmatematikk i ATHLTHCustomWorkoutTimeline. iPhone-livekort og skrivebeskyttet universell aktiv økttilstand bruker samme resultat. Ingen ny lagret økt, HealthKit-writer, GPS-sensor eller resultathistorikk er opprettet.

- Intervaller: riktig drag, hvile, rundenummer, tidsgrense og antall faktiske trinn (ingen avsluttende falsk pause).
- Tabata: 20/10-sekunder uavhengig av gamle generiske 40/20-innstillinger.
- EMOM: minutter begrenset til øktens opprinnelige varighet. AMRAP/For Time: samme cap-klokke.
- Pause: status fryses, trinn beholdes. Ugyldig tid eller konfigurasjon gir ikke en oppdiktet økt.
- Avsluttet intervalloppskrift fullfører ALDRI selve treningsopptaket. Det krever eksplisitt lagring og den autoritative originaljournalen.

Nye målrettede XCTest er lagt inn i hybrid-engine workflowen. Siste commit krever grønn build/test og fysisk Watch/iPad/HealthKit-verifikasjon før utgivelse. Ingen TestFlight-godkjenning er gitt.
