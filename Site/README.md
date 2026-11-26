# Kanal — website

Static site. No build step, no framework, one small first-party script: the
files in this folder are the site. It lives inside the app repository and is deployed by
Vercel from `magnusbomann/kanal`:

| Vercel setting | Value |
| --- | --- |
| Root Directory | `Site` |
| Application Preset | Other |
| Build Command | empty (override) |
| Output Directory | `.` |

Everything else — redirects, security headers, caching — is in `vercel.json`,
so the dashboard needs nothing more. Only this folder is uploaded; the app's
source never reaches the host.

```
index.html        the whole product story
support.html      self-service help, and where email lands
privacy.html      what is collected (nothing) and who the device talks to
terms.html        licence, and where the user's responsibility for sources begins
copyright.html    why a takedown notice cannot be served on a player
licenses.html     VLCKit LGPL notice, Wikidata, the TMDB attribution TMDB requires
404.html
demo.m3u          App Review's test playlist: public test streams and
                  Creative Commons films only. Named in AppStore/metadata.md
assets/           styles.css (every page), home.css + home.js (front page only),
                  shots/ (real app captures), icons, the OG image
vercel.json       redirects (/privacy, /support…), CSP and security headers
.vercelignore     keeps this README off the site
```

## Before it goes live

0. **Register the domain and deploy before submitting the app.** App Review
   opens the privacy URL and loads `/demo.m3u` from it; neither exists until
   this folder is live. Check both by hand afterwards:

   ```bash
   curl -sI https://kanalplayer.com/privacy | head -1
   curl -s https://kanalplayer.com/demo.m3u | head -1
   ```

1. **Set the domain.** Every canonical, Open Graph and sitemap URL currently
   says `kanalplayer.com`. `../Scripts/set-domain.sh YOURDOMAIN` changes them here and in the app
   (legal texts, Wikimedia user agent, App Store metadata) at once.

2. **Set up the mail addresses** referenced on the site: `hello@`, `privacy@`,
   `legal@`, `copyright@`. They can all forward to one inbox.

3. **Replace the App Store link.** `#get` currently points at a mailto. When the
   app is approved, point the primary button at the App Store listing and add
   the Apple smart-banner meta tag to `index.html`.

4. **Check the claims still hold.** The measured numbers on the page — 12 ms per
   search, 31 027 of 31 176 films, 657 channels — come from the app's own
   measurements. If those change, change them here.

5. ~~Add a contact URL to the Wikimedia user agent~~ — done 2026-11-24; it
   names `/support` and `hello@`, so those must work.

## Choices worth knowing about

- **One script, ours, and optional.** `assets/home.js` (about 90 lines, no
  dependencies, no network) writes scroll progress into CSS custom properties;
  every transform on the front page is `calc()` in `assets/home.css`. The CSP
  allows `script-src 'self'` and nothing else. Without the script, or with
  reduced motion, the page renders in its settled state and reads top to bottom.
- **The front page is always light.** It is a bright living room with the
  television as the one dark object in it (Magnus asked for white, 2026-11-26). The legal pages still follow the visitor's light or dark setting.
- **No inline styles.** `style-src 'self'` blocks `style=""` attributes, so
  spacing lives in the stylesheets. The script sets custom properties through
  the CSSOM, which the CSP permits.
- **Assets are cached for a year.** `home.css` and `home.js` are linked with a
  `?v=` date in `index.html`; bump it whenever either file changes.
- **No web fonts.** The condensed display face is found on the visitor's own
  system (`SF Pro Display` → `Segoe UI Variable` → `Roboto Condensed` →
  `Arial Narrow`), so the headline paints on the first frame with no layout
  shift. If a licensed face is bought later, self-host it and add `font-display:
  swap` — do not add a font CDN, it would need loosening the CSP.
- **No cookies, no analytics.** Which is why there is no cookie banner, and why
  the privacy page can be short and absolute.
- **Design tokens mirror the app.** `assets/styles.css` carries the same coral
  gradient, neutral surfaces and condensed display type as
  `KanalUI/Theme/KanalColor.swift`, and the same rule: one accent action per
  screen.
- **Scroll moves things; it never reveals them.** An earlier version hid
  content until a scroll event fired and was removed for that reason. The 3D
  scenes follow the same rule: nothing is unreadable before it animates, and
  the lowest opacity any card starts from is 0.3.
- **Contrast is checked, not assumed.** Body-copy links use `--accent-link`
  rather than the accent itself: the coral is 2.2:1 on a light background and
  would have failed WCAG AA.

## The voice, and why it is not UHF's

UHF's site swaggers, and does it well: "Your IPTV deserves better. So do you."
"A free tier so generous it makes the competition embarrassed." It picks a fight
with the category and wins it.

Out-swaggering them would be a losing game, and it would contradict the product.
Our claim is simplicity, so the copy is calm, plain and short, and its confidence
comes from being specific rather than loud. Four rules hold it together:

1. **Write about the reader, not the app.** "Set it up once. Never explain it
   again" is aimed at whoever in the family is the household's IT department.
   Every section headline is a sentence about their life, not our feature list.
2. **Two beats, and the second one turns.** Headline, then the payoff. "Three
   steps. There is no step four." "We can't lose your data. We never had it."
3. **Numbers instead of adjectives.** 12 ms. 31 027 of 31 176 films. Zero wrong
   answers. Every figure on the page came from a real measurement, so nothing
   needs to be called "blazing fast" or "powerful".
4. **Never name a competitor.** "Every other player opens by asking what an M3U
   is" makes the point without a fight, and without giving them the traffic.

## The two things this site cannot fake

UHF's page has both, and both beat any sentence we could write:

- **Social proof.** They show 4.6 stars and 5000+ reviews next to the button.
  We have no reviews yet, and inventing them is out of the question. The moment
  there are real ones, they belong immediately to the right of the primary CTA.
- **Real screenshots.** Done for the front page: `assets/shots/` is cut from
  `AppStore/screenshots/` (Apple TV home, details and player, iPhone home,
  details and live). Still missing, because no capture exists yet: the guide,
  a child's profile and the Apple TV pairing screen.

## What may be shown

Hard rule: every image on this site comes from the demo playlist (`demo.m3u`),
meaning Blender Studio open movies under CC BY and public test streams. No
poster, still or logo from a commercial film, series or channel, ever, and no
capture taken against a real provider. Commercial titles may be named in text
where the copy needs them (the Lion King search example) but never pictured.
The CC BY credit sits under the poster shelf and in the footer; keep it.

## Local preview

```bash
python3 -m http.server 8000
```
