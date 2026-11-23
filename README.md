# Flow of Ace

Mobile web app for a 5–15 minute pre-match routine: arousal tuning (synthesized audio + paced breathing), three short visual drills, position-specific visualization and cue selection, an activation card deck, and an "In the zone" summary screen.

- Source: `src/app.html` (all CSS/JS inline, no dependencies).
- Build: `./build.sh` writes `index.html` with the PWA manifest and service worker hooks.
- Run locally: `python3 -m http.server 8080`, then open http://localhost:8080. Service workers need HTTPS or localhost.
- Deploy: any static host (GitHub Pages, Netlify, Cloudflare Pages). Open once online; it then works offline.

Notes: haptics use the Vibration API, which iPhone Safari does not support. Audio is generated with Web Audio, so no audio files are needed offline.
