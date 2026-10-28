# ATHLTH Coach 2.0 – lokal styrkeintelligens (fase 1)

Referanse: GymCoach – https://github.com/gymcoach-app/gymcoach (MIT, 2026 GymCoach contributors). Vi gjenbruker prinsipper for databaserte råd, men importerer ikke deres database eller installerer en ekstra tjeneste. Språkmodellen er fortsatt ATHLTHs Groq-integrasjon – lokal analyse er ikke det samme som en lokalt kjørende LLM.

## Implementert
- ATHLTHCoachStrengthIntelligence.swift: lokal, skrivebeskyttet analyse av fullførte ATHLTH-styrkeøkter siste åtte uker. Registrerte arbeidssett, belastning, treningsvolum og konservative 1RM-estimater (1–12 repetisjoner). Ingen oppdiktede målinger, ingen ufullførte eller gamle økter, ingen oppvarmingssett.
- Foreslår kun å vurdere belastningsøkning etter to forskjellige fullførte økter som begge har nådd planlagte vekt-/repsmål. Stagnasjon vurderes over minst tre økter fordelt på minst 14 dager. Ingen endring utføres automatisk.
- Den eksisterende progresjonsvisningen viser lokale bevis og beholder eksisterende godkjenningsdialog for endringer i plan.
- AIProgramBuilderView viser hvilke treningsdata Coach har grunnlag for. Strukturert treningskontekst sendes bare når Coach-historikk er aktivert av brukeren.
- Supabase generate-training-program begrenser inngangsfeltene til et lite, validert sett med signaler, og instruerer modellen om å bevare usikkerhet, grenser og treningsplanutkast til godkjenning.
- Skader og øvelsesbegrensninger beholder separat eksplisitt samtykke og kontroll. Apple Health, Apple Watch, løpeplaner, lydcoach, gamle planer og historikk beholdes.

## Viktige begrensninger
- Dette er første fase, ikke full utskiftning av alle eksisterende coach-funksjoner.
- Lokal regelmotor er offline, mens samtaler fortsatt krever valgt ekstern AI-modell.
- Det kreves mer arbeid før gammel coach kan fjernes: samme kontekst i live-chat og stemme, ferdige lisenskontrollerte flerukers styrkeprogrammer med korrekte 1RM-bølger/deload, slutt-til-slutt iOS/Watch-testing, datamigrasjon/rollback.
- Kildekoderettigheter for etablerte kommersielle treningsopplegg må avklares separat fra MIT-lisensen for programvare.
- Ingen TestFlight uten eksplisitt instruksjon.
