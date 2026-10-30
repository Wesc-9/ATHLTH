# ATHLTH Android – utviklingsgrunnlag

**Status:** Første native Android-kode og Health Connect-lesing. Ikke ferdig app, ikke verifisert med Android-bygg eller fysisk enhet. iOS/watchOS berøres ikke.

## Hva finnes

- Kotlin + Jetpack Compose app-skall med Hjem, Trening og Profil.
- Tilkobling til eksisterende Supabase-prosjekt for **e-post/passord-innlogging**. Kontooppretting, Apple/Google OAuth, RLS-verifikasjon og tverrplattform-synkronisering gjenstår.
- Health Connect grunnlesing: skritt og økter etter eksplisitt tillatelse, valgfri puls og søvn. Manglende tilgang/data vises som «Ikke tilgjengelig»; null er ikke automatisk lik null registrerte skritt.
- Gradvis tilbaketrekkbar Health Connect-tilgang (app må kontrollere rettighetene på nytt ved lesing).
- Tidlig versjonert DTO for treningsøkter, måleproveniens og enhetstester.

### Oppstart

1. Åpne **android/** som et eget prosjekt i Android Studio (nyere kompatibel versjon, Android SDK 36, JDK 17).
2. Importer/synk Gradle. En Gradle-wrapper mangler ennå og skal genereres fra en verifisert lokal Gradle-installasjon; ikke anta at `./gradlew` fungerer før den er lagt inn.
3. Kjør `:app:assembleDebug` og `:app:testDebugUnitTest` fra Android Studio eller Gradle.
4. Test på Android 14+ eller Android 9–13 med Health Connect installert, og gi de nødvendige tillatelsene.
5. Test pålogging med en **testkonto** med bekreftet e-post/passord i eksisterende Supabase Auth, ikke med en produksjonskonto med kun Apple OAuth.
6. Kontroller i Supabase at klientnøkler er publiserbare, at RLS begrenser brukerdata og at eksisterende iOS-autorisering ikke er endret.

**OBS:** `READ_SLEEP` gir varighet av siste søvn*periode*, ikke garantert faktisk sovetid. Detaljerte søvnstadier og deduplisering må utvikles før intelligens-/restitusjonsberegninger.

## Avgrensninger

- Helseintegrasjonen er read-only. Ingen bakgrunnsimport, automatiske backup-opplastinger, GPS-opplasting eller skriving av Health Connect-treningsøkter.
- Økter fra Health Connect vises kun som et begrenset sammendrag. Godkjennings-innboks, detaljer, kontinuerlig paginering og pålitelig deduplisering må bygges.
- Felles `WorkoutPrescription` er en **foreslått ny JSON-kontrakt**, ikke bevist wire-kompatibel med nåværende Swift Codable-modeller. Krever golden fixtures og eksplisitte migrasjonsregler før produksjon.
- Ingen Wear OS-opptak, Audio Coach, Ghost Race, Coach AI, Community, eller full Train UI i første skjelett.
- Ingen Google Play-publisering, testing eller fakturering er startet.
- Den eksisterende Supabase-API-publiseringsnøkkelen er ikke en administrativ/hemmelig `service_role`-nøkkel. RLS og separate consent-gates er ufravikelige.
- Personvern-/Health apps-erklæring, tillatelsesbegrunnelser og Android Health Connect-tilgangsvilkår må gjennomgås før Play. Rationale-skjermen er foreløpig teknisk innhold, ikke endelig juridisk tekst.

Se `../docs/ANDROID_FOUNDATION.md` for arkitekturen og videre steg.
