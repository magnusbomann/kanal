# Apple TV — designgjennomgang før lansering

**Implementert etter gjennomgangen — 5. september 2026**

- Egne minimumsstørrelser for TV-tekst, bedre tekstkontrast, mørk tekst på korallknapper og tydelige fokusrammer.
- Se alle ligger ved seksjonstittelen på TV; hyllene har fokusområder. Forsiden prioriterer innhold fremfor hilsen og duplisert søk. Spill av får eksplisitt startfokus på detaljskjermen.
- TV-spilleren har fokusert tidslinje, forhåndsvisning av valgt posisjon, akselererende spoling med finjustering etter retningsbytte/pause, bekreft/avbryt og trinnvis Back. Åpne kontroller blir ikke skjult midt i brukerens navigasjon. Første visning kan skjules automatisk.
- Ett TV-oppsett med QR og separat manuell vei. Reparasjon beholder manuell reparasjonsflyt og oppretter ikke ny tjeneste via QR. Standalone paring har lukk/Back.
- Guiden viser informasjon om fokusert program uten å åpne et ark, har større rader og Til nå. Favorittvalget er synlig i live-spilleren.
- TV-tilbud begrenses til ett automatisk tilbud per appøkt og minst 24 timer mellom tilbud, også ved omstart.
- Nye tekster er lagt inn for alle 14 grensesnittspråk.

**Verifisert:** tvOS- og iOS-simulatorbygg besto. `swift test` besto med 416 Swift Testing-tester og 3 XCTest-tester, inkludert spolepolicy, tilbudspacing og lokaliseringskontroll. `git diff --check` besto. Det nye TV-oppsettet ble inspisert visuelt og dokumentert i `apple-tv-design/setup-after.png`.

**Begrensning:** den videre simulatorrunden med nytt testbibliotek lot seg ikke fullføre i den lokalt ad-hoc-signerte appen. Oppstart/oppsett virket; import ble ikke bevart, og et forsøk med midlertidige simulatorentitlements ble avvist ved oppstart. Midlertidige signeringsforsøk er ikke prosjektinnstillinger eller distribusjonsendringer. Derfor er ny forside/guide, full avspilling med begge motorene, fokusretur, Siri Remote på fysisk TV og telefon–TV-paring fortsatt manuelle kontrollpunkter. Ingen publisering eller endring av konto/signering i prosjektet.

Den opprinnelige vurderingen nedenfor er bevart som bakgrunn; implementeringsstatusen over gjelder nå.

5. september 2026. Anbefaling: behold den visuelle retningen, men ta en avgrenset tvOS-runde før bred lansering.

## Grunnlag og begrensninger

Gjennomgang av aktuell arbeidskode for forside, kort, fokusstiler, oppsett, søk, guide, detaljer og spiller. Nytt Debug-bygg for tvOS-simulator besto. Lokal ad-hoc-signering var nødvendig for å kjøre simulatorbygget; første usignerte forsøk stoppet med CODESIGNING / Invalid Page. Dette er ikke dokumentasjon på feil i distribusjonsbygget.

Forsiden ble inspisert visuelt i Apple TV 1080p-simulator med eksisterende lite bibliotek. Skjermbildet ligger i apple-tv-design/home.png. Fjernkontrollkommandoer ble forsøkt via simulatorens tastatur. Fysisk Siri Remote, full avspillingsrunde, VoiceOver og faktisk leseavstand er ikke verifisert. Kodefunn og anbefalinger nedenfor er ikke alle reproduserte runtime-feil.

## Før lansering

1. **P1: Gjør tekststørrelsene konsekvente på TV.** KanalFont beholder eksplisitte størrelser på tvOS, mens KanalMetrics bare skalerer avstander. Cards.swift bruker 15 pt tittel og 12–13 pt undertekst. GuideView bruker 10–13 pt, selv om radene er 84 pt. Badges bruker 11 pt; PlayerChrome bruker 11–16 pt. Forsiden bekrefter visuelt at korttitler, søk og Se alle er små i forhold til faner og seksjonsoverskrifter. Innfør egne semantiske TV-størrelser: prøv 28–32 pt for korttitler/handlinger og 22–24 pt for viktig sekundærtekst. Dette er foreslåtte utgangspunkter, ikke oppgitte Apple-minstekrav. Unngå blind 1,6×-skalering som også forstørrer allerede tilpassede overskrifter. Godkjenn ved 2,5–3 meters avstand med norske, lange titler.

2. **P1: Øk kontrasten i primærknapper.** KanalPrimaryButtonStyle setter hvit tekst på gradienten #FFA183–#FF6A3C. Beregnet kontrast mot endefargene er bare 1,97:1 og 2,85:1, før glass/kompositering. Selv stor knappetekst blir svak. Bruk mørk tekst på korall, eller en mørkere knapp med hvit tekst. Kontroller også tertiaryText på lys bakgrunn: #AEAEB4 mot #EFEFEF er 1,92:1. Tallene er statiske sRGB-beregninger, ikke måling av alle ferdig renderte flater.

3. **P1: Sikre fokus mellom seksjoner og kort.** Shelf har ingen eksplisitt focusSection. Med tre filmkort til venstre og Se alle langt til høyre ble Se alle stående markert etter ned/venstre-forsøk i simulatoren. Dette er en konkret observasjon som må bekreftes med fysisk fjernkontroll; ikke en bevist universell fokuslås. Legg til passende fokusområder og kontroller korte og fulle rader. Kortstilen gir 8 % forstørrelse og litt lysning, mens chips blir tydelig lyse; gi kort og øvrige kontroller en like tydelig fokusmarkering. Verifiser at tilbake fra detaljer gir samme kort, at Spill av får ønsket startfokus, og at fokus aldri forsvinner når metadata oppdateres. TitleDetailView kommenterer startfokus på Spill av, men setter det ikke eksplisitt.

4. **P1: Gi spilleren en egen TV-interaksjon.** PlayerChrome.onMoveCommand kaller skip(±10) på venstre/høyre uten å sjekke hvilken kontroll som har fokus. Dette er en interaksjonsrisiko; ikke bekreftet under avspilling her. TV-tidslinjen er bare tegnet, uten fokus eller posisjonsvalg. Å flytte seg 30 minutter krever dermed 180 ti-sekunderssteg med den viste mekanismen. Skill knappnavigasjon fra spoling, legg til fokusert tidslinje med raskere forflytning og tydelig tidsvisning, og test både AVFoundation og VLC. Back kaller alltid onClose; vurder første Back som skjul kontroller når disse er åpne, neste som tilbake. Ikke la automatisk skjuling avbryte aktiv kontrollbruk.

5. **P2: Gjør første TV-oppsett kortere og mer romslig.** Onboarding har to introduksjonssider før Welcome, som igjen viser telefonvalg og manuell lenke. Begge bruker maksbredden 640. Behold forklaringen om egen TV-tjeneste, men samle hovedvalget på én TV-side: Sett opp med iPhone, stor QR og Skriv inn manuelt som sekundær vei. Dette er en designanbefaling basert på kode, ikke en observert avbruddsrate. Verifiser at tilbake virker fra paringsskjermen og at treg import har tydelig fremdrift.

## Neste prioritet

- **Guide:** større programtekst, tydelig informasjon om fokusert program, start nær nåværende program og en enkel Til nå-handling. Tidslinjen begynner i dag en time før nå uten eksplisitt scrolling til nå. Behold festet kanalspalte og direkte avspilling av pågående programmer.
- **Favoritter:** kanaloversikten legger favorittvalget i contextMenu. Tilby en oppdagbar favoritt-handling i kanal-/spillerinformasjon, så førstegangsbrukeren ikke må kjenne langt trykk.
- **Forside:** behold Fortsett å se, favorittkanaler og siste kanaler foran redaksjonelle rader. Bruk mindre plass på hilsen og duplisert søkeinngang dersom innhold presses ned. Ikke legg til automatisk video eller en stor hero bare for å fylle et lite bibliotek.
- **Betaling:** ProNudge kan vise tilbud etter fjerde vellykkede avspilling og senere med 15 minutters startintervall. Vurder sjeldnere, øktbasert visning på TV, slik at kanalbytte ikke oppleves som en kjøpsflyt. Dette er et produktvalg, ikke en funksjonsfeil.

## Behold

Den mørke, rolige paletten med korall som aksent; få hovedfaner; plakatformatet; egne TV-detaljer med stort bakgrunnsbilde; telefonbasert oppsett; og personlige fortsett-/favorittrader. Appen trenger bedre lesbarhet og navigasjon, ikke ny visuell identitet.

## Praktisk lanseringskontroll

På fysisk Apple TV med Siri Remote: oppsett, finn norsk filmtittel, spill/pause, hopp 30 minutter, velg lyd/tekst, gå tilbake til samme kort, bytt kanal og legg til favoritt. Gjenta med langt tittelnavn, manglende bilde, kort/full rad, tom profil og avbrutt nett. Bruk en person som ikke kjenner appen, på vanlig sofaavstand. Ingen veiledning om skjulte langt-trykk-handlinger.

Apples fokusveiledning understreker tilpasning til ulike fokustilstander: https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/
Tilgjengelighet og kontrast: https://developer.apple.com/design/human-interface-guidelines/accessibility
