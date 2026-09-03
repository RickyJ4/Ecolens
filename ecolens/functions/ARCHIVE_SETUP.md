# Hazard Archive — one-time infrastructure setup

> **2026-07-28: manual setup is now OPTIONAL.** `_archive_bucket()` in
> `main.py` self-provisions the bucket on the function's first run — create,
> uniform access, public read, CORS, 90-day daily lifecycle — because the
> deploy machine has no `gcloud`. The commands below remain as reference /
> for manual recovery.

The archive functions (`archive_hazards_daily`, `archive_backfill` in `main.py`)
write daily hazard snapshots to a dedicated **public, read-only** GCS bucket.
Run these once from a shell with `gcloud` authenticated against project
`ecolens-ad854`.

## 1. Create the bucket

```sh
gcloud storage buckets create gs://ecolens-archive-ecolens-ad854 \
  --project=ecolens-ad854 --location=us-central1 \
  --uniform-bucket-level-access
```

A dedicated bucket (not the default Firebase bucket) so public read access
exposes nothing but the archive.

## 2. Public read access

```sh
gcloud storage buckets add-iam-policy-binding gs://ecolens-archive-ecolens-ad854 \
  --member=allUsers --role=roles/storage.objectViewer
```

## 3. CORS (browser fetches from the map app)

Save as `archive-cors.json`:

```json
[{"origin": ["*"], "method": ["GET", "HEAD"], "responseHeader": ["Content-Type"], "maxAgeSeconds": 3600}]
```

```sh
gcloud storage buckets update gs://ecolens-archive-ecolens-ad854 --cors-file=archive-cors.json
```

`origin: *` is acceptable here: the bucket is public read-only data.

## 4. Retention lifecycle (daily files 90 days; weekly rollups forever)

Save as `archive-lifecycle.json`:

```json
{"rule": [{"action": {"type": "Delete"},
           "condition": {"age": 90, "matchesPrefix": ["archive/v1/fires/daily/", "archive/v1/earthquakes/daily/"]}}]}
```

```sh
gcloud storage buckets update gs://ecolens-archive-ecolens-ad854 --lifecycle-file=archive-lifecycle.json
```

Note: `index.json` keeps listing days the lifecycle rule has deleted until the
next daily run rewrites it; the client treats a 404 day-file as "expired" and
falls back to the weekly rollup if one exists.

## 5. Deploy the functions

```sh
firebase deploy --only functions:archive_hazards_daily,functions:archive_backfill
```

## 6. Backfill (optional, recommended on day one)

`archive_backfill` is **closed by default** (same contract as `trigger_scout`):
bind `ADMIN_TRIGGER_TOKEN` to it in `main.py`'s decorator `secrets=[...]` list,
redeploy, then:

```sh
curl -H "X-Admin-Token: $TOKEN" \
  "https://us-central1-ecolens-ad854.cloudfunctions.net/archive_backfill?start=2026-07-18&end=2026-07-26"
```

Fires can only backfill ~10 days (FIRMS NRT window); earthquakes any range
(max 60 days per call).

## Verify

```sh
curl -s https://storage.googleapis.com/ecolens-archive-ecolens-ad854/archive/v1/index.json | python -m json.tool
curl -sI https://storage.googleapis.com/ecolens-archive-ecolens-ad854/archive/v1/fires/daily/2026/2026-07-26.geojson
# expect: content-encoding: gzip, cache-control: public, max-age=31536000, immutable
```
