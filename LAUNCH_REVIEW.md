**Kanal — produktoppdrag og gjennomgang før lansering**

5. september 2026. Anbefaling: fortsett med TestFlight, vent med bred App Store-lansering til synkronisering og de viktigste familieforløpene er verifisert.

**Samlet verifisering — 5. september 2026**

Etter autorisasjon til å teste: 415 tester i 80 suiter bestått, inkludert lokaliseringssjekken (423 nøkler), de opprinnelige synkfeilene, samtidige tillegg/slettinger, vedvarende slettemarkører, fjernsletting og utvidelse av barneprofil, krypterte importkvitteringer og tom live-import. iOS- og tvOS-simulatorbygg er bestått. En Swift 6 Sendable-kompileringsfeil i paringens timeout-gate ble rettet under kontrollen.

UI-testen avslørte ugyldige signaturer i de lokale VLC-simulatorbibliotekene (CODESIGNING / Invalid Page før main). Begge lokale simulatorbiblioteker er nå signert på nytt og verifisert. Etter reparasjonen besto en UI-test som starter appen med største Dynamic Type, ruller frem til Fortsett og går videre til neste oppsettsside. Dette viste hvorfor bygg alene ikke dokumenterer fungerende oppstart. Fysiske enheter, ekte iCloud-paring/synk, reelle strømmer og StoreKit-kjøpsforløp krever fortsatt ende-til-ende-kontroll. Den offentlige personvernadressen er fortsatt uavklart.

**Implementeringsstatus etter oppfølging — 5. september 2026**

Kodeendringer er skrevet for alle de ti funnene nedenfor, med tre avgrensede GPT-5.6-Luna-agenter. Dette er ikke en ny verifisert teststatus: på Magnus’ uttrykkelige ønske er tester og bygg utsatt til etter at rettelsene er samlet.

- Synkronisering bruker nå vedvarende versjoner per verdi, logisk klokke og slettemarkører. V3 leser eldre data, men eldre appversjoner skriver ikke til den nye nøkkelen; oppdater alle enheter før flerenhetstesten.
- Historikk i skytransporten har identitetsmetadata uten strøm- og bilde-URL-er. Avspilling må løses mot lokal katalog. Leverandøradresser og passord oppbevares separat i Keychain, som kan synkroniseres med iCloud Keychain.
- Sletting eller endring av en aktiv begrenset profil krever nytt profilvalg. Profilbytte og avspillingslagring er beskyttet mot feil profil.
- VOD lagres periodisk, ved pause, bakgrunn og lukking. Tom første live-import faller tilbake til full katalog.
- Paring venter på kryptert kvittering etter validert import, med tidsgrenser og beskyttelse mot duplikate og gamle callbacks.
- iOS-typografi følger Dynamic Type, onboarding kan rulles, og guiden skalerer og bruker kanalgrupper med alternative strømmer.
- Kjøp håndterer delvis produktliste og viser gratis prøveperiode bare for freeTrial. Personvern og vilkår finnes også innebygd, og personvernteksten beskriver faktisk iCloud/Keychain-bruk.

**Gjenstår eksternt:** bekrefte og konfigurere fungerende offentlig domene og kontaktadresse for personvern/vilkår. Innebygd tekst erstatter ikke App Store Connects krav til offentlig personvernlenke. Ingenting er publisert.

**Neste samlede kontroll:** pakke- og lokaliseringssjekker, iOS/tvOS-bygg, to enheter med samtidige endringer/sletting/omstart, familieprofil under synk, VOD etter bakgrunn, VOD-only-import, paring ved treg import/avbrudd, største tekststørrelse og StoreKit med delvis produktliste. Tidligere beståtte tester nedenfor gjelder revisjonen før disse endringene.

**Oppdraget jeg anbefaler**

> Gjøre familiens egen TV enkel å finne frem i, trygg å bruke og pålitelig å se på — uten at noen må forstå IPTV.

Den viktigste brukeren er personen som får fjernkontrollen etter at den tekniske i familien har satt opp tjenesten. Kanal lykkes når den personen kan bruke appen alene også neste uke. «Beste for de fleste» bør derfor bety færrest avbrutte seeropplevelser, minst behov for hjelp og tydeligst skille mellom appen og TV-tjenesten.

| Person | Det faktiske behovet | Hva appen må bevise |
| --- | --- | --- |
| Kari | Finne en kjent kanal eller «Løvenes konge», lese teksten og komme tilbake etter et feiltrykk | Søk med norske titler, lesbar tekst, synlig tilbakeknapp, samme kanal selv om en strøm svikter |
| Ola | Sette opp tjenesten raskt og slippe å være support for resten av familien | Fungerende import, forklarlige feil, enkel reparasjon og oppsett på TV uten å skrive lange lenker |
| Familien | Ha egne favoritter, riktig språk og fortsette der de slapp | Ingen sammenblanding eller tap ved profilbytte og synkronisering; foreldrekoden virker også etter omstart |

Dette bygger videre på det som allerede er bra: oppsett med ett felt, lokal søkeindeks og oversatte titler, kanalgrupper med alternative strømmer, egne profiler og felles spillerkontroller. Jeg ville beholdt disse investeringene. Sammenligninger med konkurrenter i README er historiske produktantakelser; denne gjennomgangen er ikke en ny konkurrenttest.

**Hva gjennomgangen faktisk dekker**

Kodegjennomgang av oppsett/import, profil- og innholdsregler, synkronisering, Keychain, historikk, søk, forside/bibliotek, TV-guide, spillerens livssyklus, telefon–TV-paring, StoreKit, språk/typografi og byggkonfigurasjon. Hele den ordinære testsuiten ble kjørt. iOS- og tvOS-simulatorbygg ble kjørt. Norsk førstegangsvisning ble åpnet på en separat iPhone 16e-simulator, og sammenlignet ved vanlig og maksimal tilgjengelighetstekststørrelse.

Dette er en bred kode- og produktgjennomgang, ikke en attest på at alle skjermer og alle strømformater er testet ende til ende. Ingen fysisk iPhone/Apple TV, reell iCloud-rundtur, kjøp i App Store-sandbox, komplett VoiceOver-gjennomgang eller leverandørabonnement ble brukt i denne runden. Avspillingskoden ble samtidig endret av annet arbeid i samme arbeidsmappe; jeg endret ikke disse filene. Endringer i den vanlige testsuitens antall inkluderer derfor også det arbeidet.

**Rettet i denne gjennomgangen**

| Feil | Før | Nå og verifikasjon |
| --- | --- | --- |
| Voksenprofil omgår kode ved oppstart | Profilvelgerens profilknapper aktiverte direkte. Omstart ga en vei rundt låsen på barneprofilen. | Voksenvalg går gjennom eksisterende kodekontroll når kode er satt. Regresjonstest av valgregelen; begge UI-bygg kompilerer. Selve kodearket må fortsatt prøves med fjernkontroll. |
| Hentede episoder omgår bibliotekfilteret | Den delte episodecachen ble returnert direkte til detaljskjermene, også etter overgang fra voksen til barn. Spillerens siste kontroll kunne stoppe avspilling, men tittel og bilde var allerede synlige. | Episodeoppslag bruker den aktive profilens regelverk. Test laster episoder som voksen, bytter til barn og kontrollerer at voksent innhold forsvinner. |
| Innlogging går tapt under migrering | Feil fra Keychain ble ignorert, og gammel JSON ble likevel tømt for innlogging. | Migrering beholder den gamle filen hvis lagringen feiler. Vanlig lagring av tjenestelisten avbryter også før overskriving ved Keychain-feil. Test simulerer feil, oppdatering og ny oppstart med fungerende lagring. |
| Oppdatering av Keychain sletter først | Eksisterende innlogging ble slettet før en ny kopi ble lagt til. Feil ved innlegging kunne etterlate ingen kopi. | Eksisterende element oppdateres med `SecItemUpdate`; et nytt element opprettes bare når det ikke finnes. Kompilert for begge plattformer; feil fra ekte Keychain er ikke fremprovosert. |

Rettingen av migrering betyr at en allerede eksisterende fil med innlogging kan bli liggende til en senere vellykket migrering. Den innfører ikke ny lagring av innlogging i JSON. Feilmeldinger ved andre disk- og Keychain-feil trenger fortsatt en egen gjennomgang.

De nye ordinære testene ligger i [LaunchReadinessTests.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Tests/KanalCoreTests/LaunchReadinessTests.swift>).

**Åpne feil og lanseringshindringer, i prioritert rekkefølge**

1. **P1 — Synkronisering mister lokale endringer. Bekreftet med kjørbar test.** `pullNewerHouseholdSnapshot` erstatter profiler og seerdata før lokale endringer slås sammen. Testen legger en favoritt på enheten og en annen i en nyere ekstern versjon: bare den eksterne blir igjen. Dette bryter familiens forventning om egne favoritter. Løsningen trenger versjonering per opplysning eller en endringslogg, eksplisitt sletting og konfliktregler. En union av favoritter alene vil gjenopplive slettede favoritter. Se [AppModel.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Store/AppModel.swift:1148>).

2. **P1 — Innlogging følger med historikken til vanlig iCloud KVS. Bekreftet med kjørbar test.** Tjenestebeskrivelsen blir renset, men `WatchState.recentItems` inneholder komplette `MediaItem.streamURL`. Xtream legger brukernavn og passord i URL-stien. Testen finner et konstruert passord i det serialiserte skyobjektet. Dataene sendes til brukerens private iCloud-område, ikke til et offentlig endepunkt, men de ligger utenfor den valgte Keychain-beskyttelsen. Bruk en egen skyrepresentasjon av historikk uten strømme- og bildelenker; rekonstruer avspillbare episoder fra tjenesten på mottakeren. Ikke bare fjern historikken og ødelegg «Fortsett». Se [WatchState.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Store/WatchState.swift>) og [HouseholdSync.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Store/HouseholdSync.swift:124>).

3. **P1 — Synkronisert profilsletting kan velge en voksen automatisk. Kodefunn, ikke fysisk testet.** Når aktiv profil mangler i den innkommende listen, brukes `profiles.first?.id`. Slett barnets profil på en annen enhet, og en voksenprofil kan bli aktiv uten kodevalg på denne enheten. Gå til en låst profilvelger når aktiv profil fjernes eller rettighetene utvides. Den nye kontrollen i profilvelgeren løser ikke denne separate synkroniseringsveien. Se [AppModel.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Store/AppModel.swift:1171>).

4. **P1 — Filmer og episoder lagrer fremdrift for sent. Kodefunn.** I VOD-spilleren skjer `recordProgress()` ved `onDisappear`; fremdriftsmeldinger fra VLC oppdaterer bare lokal visningstilstand. En app som blir drept under en lang film kan miste hele øktens posisjon. Lagre periodisk, ved pause og ved bakgrunnsovergang, og behold en siste skriving ved lukking. Prøv både AVFoundation og VLC. Se [PlayerView.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalUI/Screens/PlayerView.swift>).

5. **P1 — Gyldige Xtream-tjenester uten direktesendte kanaler avvises ved første import. Kodefunn.** Den raske importfasen kaster `emptyPlaylist` når live-listen er tom, før film-/seriebiblioteket blir prøvd. Tom live-liste bør falle tilbake til full import. Test en film-only-, serie-only- og helt tom tjeneste. Se [LibraryLoader.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Store/LibraryLoader.swift:120>).

6. **P1 — Lenker fra betalingsskjermen kunne ikke nås. Observert fra dette miljøet.** Både personvern og vilkår peker til `kanalplayer.com`. Nettleserverktøyet kunne ikke åpne sidene, og lokal HTTP-kontroll feilet med «Could not resolve host». Kontroller DNS og tilgjengelighet fra en separat forbindelse før innsending; dette er ikke bevis for global nedetid. Apple krever at appinformasjon er korrekt og at reviewer har tilgang til funksjonene. Se [ProView.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalUI/Screens/ProView.swift:246>) og [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

7. **P2 — Stor tekst gir ikke større brødtekst. Observert i simulator og støttet av kode.** Førstegangsvisningen hadde samme tekststørrelse ved vanlig og maksimal tilgjengelighetsstørrelse. `KanalFont` bruker faste punktstørrelser. Innfør semantiske tekststiler/skalert typografi, og tilpass oppsettet for store størrelser. Ikke krymp tekst for å få den til å passe. Kari skal kunne lese appen med telefonens egne innstillinger. Se [KanalFont.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalUI/Theme/KanalFont.swift>).

8. **P2 — Telefon–TV-paring kan bli stående på «kobler til». Kodefunn.** Timeouten i `PairingGuest` gjelder bare `.searching`; etter funn av TV dekker den ikke en forbindelse som aldri blir klar. `.sent` betyr dessuten at nettverkslaget behandlet sendingen, ikke at TV-en godkjente tjenesten. Legg til tidsgrense for hele forløpet og en bekreftelse fra mottakeren. Se [PairingGuest.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Pairing/PairingGuest.swift>).

9. **P2 — TV-guiden går utenom kanalgruppene. Kodefunn.** GuideView bruker enkeltstrømmer fra `library.channels` og åpner et enkelt `MediaItem`. Det kan gi flere rader for samme kanal og mister gruppebaserte alternativer fra den vanlige kanalvisningen. Bruk kanalgrupper og samle programdata fra variantene. Se [GuideView.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalUI/Screens/GuideView.swift:190>).

10. **P2 — Et rabattert introduksjonstilbud kan omtales som gratis. Betinget kodefunn.** `introductoryOffer` sjekker kvalifisering, men ikke `paymentMode == .freeTrial`; visningen behandler alle introduksjonstilbud som en gratis prøveperiode. Dette slår til dersom App Store Connect får et betalt introduksjonstilbud. Test også manglende årsprodukt, Ask to Buy, tilbakekall og utløp. Se [PurchaseStore.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalCore/Purchase/PurchaseStore.swift>).

Synkroniseringens status bør også være mer nøktern: et vellykket `synchronize()` beviser ikke at en annen enhet har mottatt data. Apple dokumenterer at kallet ikke tvinger nye verdier opp til iCloud. Den nåværende tidsstempelstyrte publiseringen ved hvert synkroniseringsforsøk bør erstattes med endringsstyrt publisering og en egen sperre for samtidige synkroniseringsjobber. [Apple: synchronize()](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/synchronize()).

De to bekreftede, fortsatt åpne synkroniseringsfeilene har [egne reproduksjonstester](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Audit/SyncAuditProbes.swift>). De ble kopiert inn i testmålet, kjørt og feilet på akkurat de beskrevne forventningene. Kopien ble deretter fjernet fra den ordinære testsuiten; originalen er beholdt her som bevis og som utgangspunkt for rettingen. En grønn ordinær suite må ikke tolkes som at disse feilene er borte.

**Ekstra distribusjonsfunn fra det samtidige avspillingsarbeidet:** Den nye [LiveChannelPlayer.swift](</Users/magnusbomann/Documents/Development/IPTV /Kanal/Packages/KanalKit/Sources/KanalUI/Screens/LiveChannelPlayer.swift:33>) bruker `systemUptime` til tidsmåling. Begge appenes personvernmanifester hadde fortsatt tom `NSPrivacyAccessedAPITypes` ved sluttkontrollen. Dette bør behandles som P1 før innsending: deklarer faktisk bruk, eller fjern API-avhengigheten. Apples begrunnelse `35F9.1` dekker måling av tid mellom hendelser i appen. Jeg har ikke endret filene som tilhører det samtidige arbeidet. [Apple: påkrevde API-begrunnelser](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

**Produktvalg som vil gjøre størst forskjell**

Jeg ville prioritert tre løfter i produktet og markedsføringen: «Finn det du kjenner», «Fortsett der du slapp» og «Hele familien finner frem». Forsiden bør ha fortsett, favorittkanaler med hva som går nå, og et begrenset antall relevante forslag. Tjenestemerker og store anbefalingsrader må ikke fortrenge det folk bruker hver dag, eller skape inntrykk av at et Netflix-abonnement følger med.

Oppsettet bør hjelpe både personen med en lenke og personen som ikke vet hvor lenken finnes. Forklar konkret hva Kanal støtter og hva som må komme fra TV-leverandøren. «TV-tjenesten du allerede betaler for» kan ellers høres ut som at ethvert vanlig kabel-TV- eller strømmeabonnement virker. Gi hjelp uten å kreve kunnskap om M3U, EPG eller dekodere.

For barn: gjør første godkjente kanal eller serie tilgjengelig med en gang, vis hvorfor annet innhold er skjult, og gi forelderen en direkte godkjenningsvei. Ikke bruk sjanger som bevis for alder. De eksisterende strenge reglene er en styrke, men en tom barneforside må forklares og kunne fylles enkelt. Foreldrekoden er enhetslokal mens profilene synkroniseres; mottakeren må forstå at låsen må settes opp også der.

For betaling: behold en brukbar gratisutgave og unngå at vanlig kanalbytte føles som en salgstrakt. Vurder betalingspåminnelsene mot faktiske seerøkter, ikke bare antall åpninger av spilleren. Forklar nøyaktig hva Pluss tilfører og hva Apple Familiedeling faktisk dekker. Familiedeling av kjøp og deling av profiler mellom forskjellige Apple-kontoer er to ulike ting; dagens private KVS-synkronisering er ikke en generell familiegruppe.

Kravet om iOS/tvOS 26 er et bevisst rekkeviddevalg. Ikke lov «for de fleste» uten å kjenne hvilke enheter målgruppen faktisk bruker. Dette er et produktvalg som må måles, ikke et forslag om å senke minimumsversjonen uten å vurdere API-bruken.

Jeg ville utsatt multiview, opptak og flere anbefalingsflater til disse løftene sitter. Catch-up og rask kanalnavigasjon kan være verdifulle senere, men kan ikke kompensere for tapte favoritter eller et barn som slipper forbi kodekontrollen.

**En konkret vei til lansering**

| Rekkefølge | Leveranse | Ferdig når |
| --- | --- | --- |
| 1 | Pålitelig familie- og synkroniseringsmodell | Begge reproduksjonstestene passer; samtidig redigering/sletting, sen Keychain-levering og profilutvidelse er testet; aktive barn får aldri automatisk voksenadgang |
| 2 | Robust seerøkt | Gjenopptakelse overlever avsluttet prosess; import virker uten live-kanaler; sviktende strømmer og nettverk har forståelig reparasjon |
| 3 | Lesbar og enkel daglig bruk | Stor tekst og VoiceOver fungerer; Apple TV kan betjenes med fjernkontroll fra start til slutt; barnet får en forståelig startside |
| 4 | Verifisert distribusjon | Virksomme vilkår/personvernsider, korrekte App Store-produkter og personvernopplysninger, og reviewer kan prøve reelt innhold det finnes nødvendige rettigheter til |

App Review krever full tilgang til funksjonene og forklaring av ikke-opplagte funksjoner/kjøp. Lag derfor en konkret review-oppskrift med en fungerende, autorisert testkilde. Kontroller at personvernopplysninger og lisens-/metadataomtale samsvarer med faktisk nettverksbruk og de medfølgende bibliotekene. Dette er punkter å verifisere, ikke en påstand om at appen blir avvist. [Apple: før innsending](https://developer.apple.com/app-store/review/guidelines/).

Prøv deretter fem personer som ikke kjenner prosjektet, hvorav minst én bruker stor tekst og to bruker Apple TV. Be dem sette opp, finne en kjent tittel, velge lyd/tekst, finne tilbake, gjenoppta og bruke en barneprofil. Observer uten å instruere. Foreslåtte akseptmål, ikke målte resultater: minst fire av fem klarer oppsett uten hjelp; alle finner tilbake fra spilleren; ingen mister fremdrift eller favoritter; ingen barneprofil åpner vokseninnhold. Mål tid til første bilde separat fra leverandørens feil og på kjent fungerende teststrømmer.

**Verifisert denne runden**

- Ordinær suite: 403 tester i 77 suiter passerte, inkludert lokalisering og tre nye regresjonstester. Første kjøring hadde 391 tester. En mellomkjøring fanget uferdige lokaliseringsnøkler fra det samtidige avspillingsarbeidet; siste kjøring passerte.
- To separate synkroniseringsprober bekreftet to åpne feil; de er ikke med i tallet for den grønne sluttsuiten.
- Debug-bygg for generisk iOS Simulator og tvOS Simulator lykkes etter rettelsene. Signaturkontroll av simulatorappene lykkes.
- Norsk onboarding åpnet på en ny iPhone 16e-simulator; samme brødtekststørrelse ble observert ved maksimal Dynamic Type.
- Ingen publisering eller endring av App Store Connect. Arbeidsmappen hadde allerede mange ucommittede endringer, og mine endringer er også latt stå ucommittet for gjennomgang.
