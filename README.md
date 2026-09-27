# Itri

Training and recovery in one app. **Training** reads your sessions (load, fitness and fatigue, sports, efforts). **Recovery** reads your nights (sleep score and stages, HRV against your normal range, resting heart rate). A switch in the middle of the tab bar flips between them: same layout, different palette (warm graphite and gold for Training, midnight and moonlight for Recovery). One **Coach** sits in both and answers from your exact numbers plus published research.

It runs on a real Garmin Connect export when one is converted, and falls back to deterministic sample data otherwise (sample training and matching sample nights). Switch in Profile → Data.

Itri merges the earlier Itri Fitness and Itri Sleep apps. Itri Sleep's backend (FastAPI + Gemini + Qdrant) lives on in `backend/` as the coach.

## Run

```bash
flutter create --org com.itri --project-name itri_fitness --platforms=ios,android,macos,web .   # first time only: adds platform folders
rm -f test/widget_test.dart                                                                    # the template test targets a counter app
flutter pub get
flutter analyze && flutter test
flutter run            # or: flutter run -d chrome / -d macos
```

## Live sync (Garmin via intervals.icu)

Garmin's own API is only open to companies, so live data comes through [intervals.icu](https://intervals.icu), an official Garmin partner:

1. Create a free intervals.icu account and connect Garmin (Settings → Connections), with activities and wellness switched on.
2. Copy the API key from Settings → Developer Settings.
3. In Itri: Profile → Live sync → paste the key → Connect.

After that the watch syncs to Garmin Connect, Garmin pushes to intervals.icu, and Itri pulls anything new when it opens, whenever it comes back to the foreground (at most every 2 minutes), or on pull-to-refresh on Today and Recovery. The key sits in the iOS Keychain. The synced data sits in a JSON file in the app's private storage, and each sync lists everything since the export ended (so history Garmin backfills late is still picked up) but downloads only sessions it hasn't seen.

Sessions go through the same processing as the export converter: 5 s resampling, pauses collapsed, GPS removed within 500 m of start and finish. Nights from intervals.icu carry the sleep score, time asleep, HRV and resting HR, but no stages or bed times. Garmin's personal HRV range isn't exposed either, so the app computes one: the previous 60 nights, mean ± 1.75 SD of log HRV. On 211 nights where Garmin's range is known, it gives the same below/within/above verdict 97 % of the time.

The export (below) stays useful as full-detail history. Where both have the same session or night, the export's copy wins.

## Real data (Garmin export)

1. Garmin Connect → Account → *Export your data* (arrives as a zip within ~48 h). Unzip it.
2. Convert it:

```bash
pip3 install fitdecode
python3 tools/garmin_import.py ~/Desktop/NEWGARMIN     # writes assets/private/garmin_bundle.json
```

3. Restart the app (a full restart, not hot reload: assets are bundled at build time).

The converter reads every night of sleep (bed and wake times, stages, Garmin's score and sub-scores), overnight HRV with Garmin's personal baseline, and daily resting heart rate, stress and Body Battery. It also reads the activity FIT files, collapses pauses, resamples to 5 s, removes GPS within 500 m of every start and finish (and all GPS for court and pitch sports), and keeps Garmin's own load and training-effect figures next to ours. `assets/private/` is git-ignored because it holds personal data.

**Model check.** On the first export (221 sessions, Jul 2025 – May 2026) the app's heart-rate load correlates with Garmin's load at r = 0.88. Agreement is strongest on steady sports (cycling 0.92, tennis 0.90) and weakest on stop-start ones (squash 0.55, strength 0.47), where Garmin's EPOC-based model counts short bursts that heart rate alone underweights.

## Recovery

| | |
|---|---|
| Readiness | Transparent morning verdict: HRV vs your usual range (counts double), resting HR vs your 30-day average, last night's score and length, training form. 0 flags → Ready or Steady, 2 → Go easy, 3+ → Recover. Every factor is shown. |
| Nights | Every night with score, stages, bed and wake times; each night links to the training day before it. |
| Trends | Score, time asleep, HRV, resting HR and bedtime over time; training vs the next night; bedtime regularity; HRV against your range. |

## Coach

The app builds a compact "facts" block on the phone (readiness, load, this and last week, the last 14 days of sessions and nights, per-sport totals, training-vs-sleep patterns) and sends it with each question. The backend retrieves 3 research summaries from Qdrant and asks Gemini to answer from both, using only the numbers it was given. The app then checks every figure in the reply against the facts and says so under the answer.

Personal nights are no longer retrieved by vector similarity: exact numbers computed in code are more accurate for questions like "how did I sleep last week?". RAG stays for the research papers (18 sleep + 7 training/recovery).

```bash
cd backend
pip install -r requirements.txt
# .env: GOOGLE_API_KEY, QDRANT_URL, QDRANT_API_KEY
python ingest_research.py        # optional: the server re-seeds on boot when the paper list changes
uvicorn main:app --reload --port 8000
./run.sh --dart-define=COACH_URL=http://localhost:8000
```

By default the app talks to `https://itri-sleep-app.onrender.com`.

### Deploy (Render)

The existing Render service keeps its URL and environment variables; only its source changes.

1. Render → the `itri-sleep-app` service → Settings → Build & Deploy.
2. Repository: `MehdiTouhami/itri`, branch `main`.
3. Root Directory: `backend` (Dockerfile path `./Dockerfile`, context `.`).
4. Environment: `GOOGLE_API_KEY`, `QDRANT_URL`, `QDRANT_API_KEY` (already set).
5. Manual Deploy → Deploy latest commit.

On boot the server compares the `research_papers` collection with the paper list and re-seeds it when they differ, so the first deploy replaces the old 18 sleep papers with all 25 (about a minute, rate-limited embedding). Check with `curl https://itri-sleep-app.onrender.com/health`.

### Security

- The Gemini and Qdrant keys exist only as environment variables on the server. They are not in the app or the repo.
- The coach endpoints require an app key (`X-Itri-Key`, server env `ITRI_APP_KEY`). The app reads it from the git-ignored `secrets.json` via `./run.sh` (`--dart-define-from-file`). A key shipped inside an app can be extracted, so this keeps casual traffic out rather than being real user auth; per-user sign-in comes before any public release.
- Rate limits: 20 questions per 10 minutes per device, 300 per hour in total.
- Resilience: if Gemini reports a model as overloaded, the coach falls back to `gemini-3.7-flash`, then `gemini-3.5-flash-lite` (set `GEMINI_MODEL` / `GEMINI_FALLBACKS` on the server to change them), and retries briefly before telling the user. Messages are capped at 2,000 characters.
- No CORS unless `ALLOWED_ORIGINS` is set; API docs are disabled; errors reach the app as a generic message and the details stay in the server log.
- The intervals.icu key lives in the iOS Keychain.

## Structure

```
lib/
  app/            router (7-branch shell + detail routes), tab bar with the Training/Recovery switch
  core/
    theme/        tokens (Training + Recovery, each dark + light), type roles, ThemeData
    charts/       hand-painted chart kit: synced telemetry traces, route trace,
                  fitness/fatigue chart, weekly bars, consistency heatmap, scrub gesture
    widgets/      primitives: Eyebrow, SectionHeader, Readout, ReadoutGrid, ZoneStrip, Pressable
    format.dart   units, pace, durations
  domain/         Activity + Sample (mirror FIT session/record), HR zones, TRIMP,
                  fitness/fatigue/form, splits, efforts, sport summaries,
                  SleepNight + RecoveryData, readiness, sleep stats, coach facts
  data/           repositories; synthetic training + sleep; Garmin bundle loader + merge;
                  intervals.icu client, mapper, incremental sync, on-device store; coach client
  state/          Riverpod providers (athlete, zones, analyses, load series)
  features/       today, log, sports, activity · recovery, nights, night, trends · coach · profile
test/             domain tests, bundle parsing tests, an app smoke test
tools/          garmin_import.py (Garmin export -> app bundle)
backend/        FastAPI coach: facts + research RAG, streaming
```

The UI never touches the data source directly. It reads `ActivityRepository`. Only two providers are async (the bundled export and the live store on the phone); everything downstream is synchronous, so a finished sync swaps data in place without sending screens back to a spinner.

## The analytics

| Metric | Definition |
|---|---|
| HR zones | Garmin default: 50/60/70/80/90 % of max HR. Editable in Profile. |
| Load (TRIMP) | Banister: minutes × HRR × 0.64·e^(1.92·HRR), summed per sample. |
| Fitness | 42-day exponentially weighted average of daily load (CTL). |
| Fatigue | 7-day exponentially weighted average (ATL). |
| Form | Yesterday's fitness − fatigue (TSB). Status is read from form ÷ fitness. |
| Splits | Crossing times interpolated between samples; the last split is partial. |
| Effort | 10 s or more at or above the zone 4 floor (80 % of max HR). Built for stop-start sports. |
| Recovery | HR at an effort's peak minus HR 60 s later. Averaged per session (3+ efforts) and per sport. |
| Load / hour | Load divided by hours, so sports with different session lengths compare fairly. |

## Synthetic data

`SyntheticGenerator` is seeded, so the same "today" always gives the same history. It follows a 3-build / 1-recovery block with a weekly template (strength, intervals, endurance ride, tempo, walk, long run, long ride). Pace improves about 5 % across the block. HR lags effort and drifts on long sessions, speed responds to gradient, and routes are closed loops that start in Preston.

## Design

- Warm graphite background, with the Itri gold shared with Itri Sleep. Colour is only used for meaning: HR zones and form.
- Fonts: Barlow Condensed for numbers, IBM Plex Sans for text, IBM Plex Mono for labels and data. They're bundled under `assets/fonts` (OFL).
- The zone palette was checked for colour-blind separation. Zones always carry a Z1–Z5 label as well as a colour.
- Sections are separated by hairlines, not cards. One drag scrubs every telemetry chart and the route marker together.
