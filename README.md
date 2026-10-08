# RDRS - Ransomware Detection and Response System

A **defensive, educational** tool that watches folders for ransomware-like
*behavior* (mass rewrites with encrypted-looking data, mass renames, extension
changes), scores the threat from 0 to 100, and responds with alerts, evidence
copies and incident reports. It never runs real malware and, by default, only
*simulates* response actions.

```
watchdog events --> entropy (64 KB sample) --> SQLite
                          |
              60-second sliding window (engine)
                          |
        weighted rules -> score 0-100 -> Normal / Warning / Critical
                          |
   Warning: alert        Critical: incident + evidence copy + simulated action
                          |
              FastAPI  -->  dashboard  +  JSON / CSV / HTML / PDF reports
```

## Quick start

```bash
python -m venv .venv
source .venv/bin/activate            # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python -m app.main --watch ./data/sandbox     # live monitor (Phase 1-5)
python -m app.main --serve                    # monitor + API + dashboard
# open http://127.0.0.1:8000
```

In a **second terminal**, trigger a safe simulation:

```bash
python scripts/sandbox_attack_sim.py                # attack-like burst -> Critical
python scripts/sandbox_attack_sim.py --cleanup      # remove its files afterwards
python scripts/sandbox_attack_sim.py --mode benign  # normal edits -> stays Normal
```

Then:

```bash
python -m app.main --list-incidents
python -m app.main --report 1 --formats json,csv,html,pdf     # writes to ./reports
python -m app.main --scan ./data/sandbox                      # one-off entropy scan
```

## How detection works

| Signal | Points | Fires when (per 60 s window, all configurable) |
|---|---|---|
| rapid_encryption | 40 | at least 20 files hold encrypted-looking data (entropy >= 7.2) |
| mass_rename | 30 | at least 15 renames, or 10 extension changes |
| high_entropy | 25 | average entropy of written files >= 7.0 (needs 5+ samples) |
| cpu_spike | 15 | suspect process uses >= 60% CPU |
| unknown_program | 10 | suspect process is not in `trusted_processes` |

The total is capped at 100. **Normal** < 40, **Warning** 40-69, **Critical** >= 70.
Process signals only *corroborate*: they are ignored unless a file-based signal
has already fired. Everything lives in `config.yaml`.

Worked example (the sandbox simulation): 40 + 30 + 25 = **95, Critical**.

## Project layout

```
app/core/        config, entropy, models, logging
app/detectors/   monitor (watchdog), engine (window), scoring, processes,
                 response (incident + quarantine), pipeline (glue)
app/database/    SQLite storage
app/api/         service logic + FastAPI routes
app/dashboard/   offline single-page dashboard
app/reports/     JSON / CSV / HTML / PDF generator
app/runtime.py   wires everything and runs background threads
scripts/         sandbox_attack_sim.py (safe test trigger)
tests/           96 tests
```

## REST API

`GET /health /status /alerts /events /scores /top-files /incidents /incidents/{id} /reports`,
`GET /reports/download/{name}`, `POST /reports/{incident_id}?formats=json,csv,html,pdf`,
`POST /scan`, `POST /settings`. Interactive docs at `/docs`.

Set `RDRS_API_TOKEN` to require an `X-API-Token` header on the POST calls.
`POST /settings` can tune thresholds, weights, levels and the window only;
`simulation_mode` and file paths cannot be changed through the API.

## Testing

```bash
pytest --cov=app                         # or: python -m unittest discover -s tests -t .
```

Covers entropy, config validation, window/scoring logic and boundaries, the
database, event translation, the full pipeline (burst -> Critical -> incident ->
evidence, with hashes proving originals are unchanged), cooldowns and decay,
reports (including HTML/CSV injection safety), the API service, the CLI, the
simulator's safety guards, and a **real-time end-to-end test** using the actual
file watcher. HTTP-level tests run automatically when `fastapi`/`httpx` are installed.

## Docker

```bash
docker compose up --build        # dashboard on http://127.0.0.1:8000
```

Data, logs and reports are mounted from the host. The port is published on
localhost only, and the container runs as a non-root user.

## Safety design

- **Simulation by default.** Termination is log-only; real process killing is
  intentionally not implemented.
- **Evidence is copied, never moved or changed.** Symlinks, oversized and missing
  files are skipped; each copy gets a SHA-256 in `manifest.json`.
- **RDRS ignores its own files** (database, logs, reports, quarantine) so it
  cannot trigger on itself.
- **Untrusted file names** are escaped in HTML/PDF and neutralised in CSV; the
  dashboard writes them with `textContent`.
- **API binds to localhost**; scans are limited to watched folders; report
  downloads block path traversal.
- The simulator refuses to run outside a folder named `sandbox`, only touches
  files it created itself, and never overwrites existing files.

## Known limitations (be upfront about these in your write-up)

- **False positives:** bulk-copying compressed files (JPEG, ZIP) also produces
  high entropy; the tests show this yields *Warning* (65), not Critical, because
  there are no mass renames. Backup tools that rename many files can score higher;
  tune thresholds or add paths to `ignore_paths`.
- **Detection, not prevention:** RDRS alerts and preserves evidence; it does not
  stop encryption.
- **Evidence timing:** the incident fires as soon as the score turns Critical, so
  evidence covers files affected up to that moment (max 25 by default).
- **Process attribution is best-effort polling.** Short-lived processes can exit
  before they are sampled (the sandbox script usually does), so "suspect process"
  is often empty in the demo. Some platforms deny per-process I/O counters.
- Entropy uses the first 64 KB of each file.
- Not a replacement for endpoint security, backups or network defenses.

## Troubleshooting

- *No events appear:* make sure the folder you change is inside `watch_folders`.
- *Duplicate event counts:* editors often write a file several ways; detection
  counts distinct files, so scores are not inflated.
- *Linux inotify limit:* very large trees may need a higher
  `fs.inotify.max_user_watches`.
