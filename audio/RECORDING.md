# Recording the coach voice

Recorded clips replace the phone's synthetic voice wherever a file exists. Record in a quiet room, phone 20 cm from your mouth, normal speaking voice. Export as MP3 (mono, 64–96 kbps).

Save files as `audio/<lang>/<key>.mp3` (for example `audio/cs/in_nose.mp3`) and list them in `audio/manifest.json`:

```json
{ "cs": { "in_nose": "audio/cs/in_nose.mp3", "in_nose.calm": "audio/cs/in_nose.calm.mp3" } }
```

Optional mood versions: add `.calm` (slower, softer, for calming down) and `.hype` (faster, brighter, for firing up) takes of the same line. The app picks the version that matches the player's energy and falls back to the plain file.

Lines containing {x} include the player's own cue or goal and stay with the phone voice.

## Čeština

| key | line |
|---|---|
| `in_nose` | Nádech nosem |
| `out_mouth` | Výdech ústy |
| `out_nose` | Výdech nosem |
| `hold` | Zadrž dech |
| `rest` | Dýchej normálně |
| `power` | Silné dýchání. Nádech nosem, výdech ústy. Drž rytmus. |
| `tune_done` | Dobře. Teď ohodnoť svou energii. |
| `reframe_nervous` | Řekni nahlas: Těším se. |
| `reframe_calm` | Řekni nahlas: Jdu si to užít. |
| `headphones` | Sundej sluchátka. Vnímej kurt. |
| `mid_high` | Zklidni se. Dlouhé výdechy. |
| `mid_low` | Přidej energii. Silné dýchání. |
| `mid_right` | Takhle to drž. Pomalé, klidné dýchání. |
| `p_breath` | Dechový trénink. Sleduj kruh. |
| `p_img` | Trénink představivosti. Zavři oči a sleduj každou scénu svýma očima, ve skutečné rychlosti. |
| `p_reset` | Trénink resetu. Ťukni po každém bodu. |
| `p_clutch` | Trénink podání pod tlakem. Před každým podáním ťukni na Start. |
| `made` | Bylo dobře? |
| `done` | Hotovo. Dobrá práce. |

## English

| key | line |
|---|---|
| `in_nose` | Breathe in through your nose |
| `out_mouth` | Breathe out through your mouth |
| `out_nose` | Breathe out through your nose |
| `hold` | Hold |
| `rest` | Breathe normally |
| `power` | Power breaths. In through the nose, out through the mouth. Follow the beat. |
| `tune_done` | Good. Rate your energy now. |
| `reframe_nervous` | Say it out loud: I’m excited. |
| `reframe_calm` | Say it out loud: I get to play. |
| `headphones` | Headphones off. Tune in to the court. |
| `mid_high` | Bring it down. Long breaths out. |
| `mid_low` | Turn it up. Power breaths. |
| `mid_right` | Stay right there. Slow, steady breathing. |
| `p_breath` | Breathing practice. Follow the circle. |
| `p_img` | Imagery practice. Close your eyes and see each scene from your own eyes, at real speed. |
| `p_reset` | Reset practice. Tap after each point. |
| `p_clutch` | Clutch serve practice. Tap Go before each serve. |
| `made` | In? |
| `done` | Done. Nice work. |
