# Flow of Ace

Mobile web app for a 5–15 minute pre-match routine: energy and nerves check-in, adaptive breathing with synthesized music tempo, a mindset step (reframe, process goal, cue, if-then plan), position-specific visualization, an activation card deck (with an optional 20-second eye primer), and a lock-in screen. In-match tools: between-sets check-in and a clutch-serve routine. Post-match flow ratings let the app learn each player's energy zone and best breathing method.

- Source: `src/app.html` (all CSS/JS inline, no dependencies).
- Build: `./build.sh` writes `index.html` with the PWA manifest and service worker hooks.
- Run locally: `python3 -m http.server 8080`, then open http://localhost:8080. Service workers need HTTPS or localhost.
- Live: https://nguyet75.github.io/flow-of-ace/ (GitHub Pages, served from the `main` branch root). Open once online, then Add to Home Screen; it works offline after that.

Accounts: optional sign-in (Google or email) with synced history, teams and a coach dashboard, using Supabase. Practice mode for training days and a voice coach in English and Czech. See [SETUP.md](SETUP.md) to turn it on; without it the app stores everything on the device.

Languages: full English and Czech interface (auto-detected, EN/CZ switch on the home screen). Czech strings live in the `FOA_CS` dictionary in `src/app.html`.

Pilot: guides for players and coaches, the pilot plan and a printable QR poster are at `/pilot/` (https://nguyet75.github.io/flow-of-ace/pilot/). The in-app pilot check-in runs at the start and after 6 weeks; `supabase/pilot_report.sql` has the queries to read the results.

Notes: haptics use the Vibration API, which iPhone Safari does not support. Audio is generated with Web Audio, so no audio files are needed offline.
