# ATHLTH Ghost Race – fase 3–5 QA-matrise

**Gren:** `release/v1.7.4`. Dette dokumentet er et testgrunnlag, ikke bevis på at fysiske tester er gjennomført.
Ikke distribuer til TestFlight før bygg og regresjoner er grønne og en eksplisitt opplasting er bestilt.

## Automatiske regresjoner

| Område | Tester | Akseptkriterium |
|---|---|---|
| Felles Ghost-tidslinje | `ATHLTHGhostTimelineTests`, `ATHLTHGhostRaceScenarioTests` | Kontinuerlig GPS/tid, samme inversberegning, ingen NaN/Infinity |
| Målpassering | `GhostRacePrivacyTests`, `ATHLTHGhostRaceScenarioTests` | Ingen seier ved 95 %, GPS-teleport eller stopp uten rutedekning |
| Fersk GPS og forbikjøring | `ATHLTHGhostLeadTrackerTests`, `ATHLTHLiveGhostWatchSignalTests` | Støy og foreldede målinger får ikke etablere nye lederskifter |
| Live synkronisering | `LiveGhostSynchronizedLaunchGateTests`, `LiveGhostWatchReconnectTests` | Begge READY, serverstart bekreftet, ingen ny økt ved reconnect |
| Live målgang og Arena | `ATHLTHLiveGhostFinishConfirmationTests`, `ATHLTHLiveGhostResultEvidenceTests` | Første registrerte målgang står, tvilsomme sluttider krever gjennomgang |
| Sluttfase-coaching | `ATHLTHGhostFinishPaceCoachTests` | Ingen umulige/urimelige fartsmål annonseres |
| Varsler og Coach-prioritet | `GhostRaceCadenceTests`, `AudioCoachAlertChannelsTests` | Kilometeroppdateringer og Ghost-haptikk kolliderer ikke |

## Fysisk validering – må utføres før lansering

1. **Replay (iPhone)**: Løp samme rute roligere og raskere enn referansen. Sammenlign live forsprang, registrerte kilometer og målt sluttid. Stopp 100 m før mål – ingen seier.
2. **Replay (Apple Watch)**: Sammenlign tallene ved samme GPS-posisjon med iPhone. Sjekk Ghost-fokus, kart, haptikk og Always-On både med hevet og senket håndledd.
3. **Mål-Ghost**: Velg jevn fart, negativ splitt og progressiv fart. Kontroller at sluttid og påkrevd tempo i sluttfasen er matematisk konsistente.
4. **Live Ghost – iPhone mot Watch**: Kjør begge READY, nedtelling og start. Bekreft én HealthKit-økt per deltaker og én delt live-økt. Mål faktiske tidsavvik mot serverens start.
5. **Live Ghost – bakgrunn og nettbrudd**: Lås skjerm, bytt app, slå av/på nett og koble fra telefon/Watch. Mål GPS-ferskhet, reconnect og varsel om utdatert forsprang. Ingen dobbel start eller målgang.
6. **Live Ghost – DNF**: Avbryt delt duell mens personlig trening fortsetter. Ingen vinner, score eller feilaktig fullført økt.
7. **Arena**: Registrer gyldig 1-mot-1, tid som avviker fra felles start, uavgjort og manglende motstandertid. Kun plausible resultater skal gi automatisk forslag til manuelt godkjent runderesultat.
8. **Tilgjengelighet**: Test Norsk/English, stor tekst, VoiceOver, redusert bevegelse, iPhone kompakt skjerm og Watch Always-On.
9. **Effektforbruk**: Sammenlign batteri og minne i 30–60 minutters Watch-løp med kart åpent/lukket og skjerm nede. Ingen kontinuerlig kartanimasjon i Always-On.
10. **Regresjon**: Normal løping, Quick Run, HealthKit-import, Audio Coach og Arena uten Ghost skal fungere uendret.

## Godkjenningsgrenser

- **Bygg:** iPhone og Watch må kompilere uten feil på riktig commit.
- **Eksakthet:** Samme loggede input skal gi samme avstands- og tidsberegning på begge enheter.
- **Datakvalitet:** Uverifisert GPS, manglende målpassering eller uoverensstemmende live-klokke kan ikke kåres til sikker seier.
- **Separat registrering:** En delt duell skal aldri utløse en ekstra HealthKit-økt ved gjenopptakelse.
- **Arena:** Forhåndsutfylt resultat er kun forslag, aldri automatisk poengtildeling.
- **Tilstand og batteri:** Nettbrudd gir kontrollert utdatert-status uten å miste lokalt registrert trening.

## Åpne punkter

- Fysisk testing av synkronisering, GPS og batteri kan ikke erstattes av Swift-enhetstester.
- Backendenes faktiske deploy-status må kontrolleres før Live Ghost/Arena regnes som endelig testet.
- Ved uenige tider bør løpsresultatet ha sporbar dokumentasjon og manuelt godkjenningssteg.
