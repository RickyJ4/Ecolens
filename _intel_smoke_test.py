"""Smoke-test every URL the intelligence-layers module hits in production.
Prints HTTP status, latency, sample feature counts and a couple of records."""
import urllib.request, json, ssl, time, re
from datetime import datetime, timedelta

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def get(url, headers=None, timeout=30):
    req = urllib.request.Request(url, headers=headers or {})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            body = r.read()
            return r.status, body, time.time() - t0
    except Exception as e:
        return None, str(e).encode(), time.time() - t0

def build_grid(lat_step, lon_step, max_lat=70, min_lat=-60):
    pts = []
    for lat in range(min_lat, max_lat + 1, lat_step):
        for lon in range(-170, 171, lon_step):
            pts.append((lat, lon))
    return pts


print("=" * 70)
print("1. WIND VECTORS  -  Open-Meteo forecast")
print("=" * 70)
pts = build_grid(20, 30)
lats = ",".join(f"{p[0]:.2f}" for p in pts)
lons = ",".join(f"{p[1]:.2f}" for p in pts)
url = (f"https://api.open-meteo.com/v1/forecast?latitude={lats}&longitude={lons}"
       f"&current=wind_speed_10m,wind_direction_10m,temperature_2m&timezone=UTC")
status, body, elapsed = get(url)
print(f"  grid points requested: {len(pts)}")
print(f"  HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    data = json.loads(body)
    arr = data if isinstance(data, list) else [data]
    with_wind = [d for d in arr if d.get("current", {}).get("wind_speed_10m") is not None]
    print(f"  features with wind: {len(with_wind)} / {len(arr)}")
    if with_wind:
        s = with_wind[0]
        c = s["current"]
        print(f"  sample: lat={s['latitude']:.1f} lon={s['longitude']:.1f}  "
              f"wind={c['wind_speed_10m']} km/h at {c['wind_direction_10m']} deg  "
              f"temp={c['temperature_2m']} C")
        speeds = sorted(d["current"]["wind_speed_10m"] for d in with_wind)
        print(f"  speed range: {speeds[0]:.1f} - {speeds[-1]:.1f} km/h  (median {speeds[len(speeds)//2]:.1f})")

print()
print("=" * 70)
print("2. 48h PRECIPITATION  -  Open-Meteo forecast")
print("=" * 70)
pts = build_grid(15, 25)[:80]
lats = ",".join(f"{p[0]:.2f}" for p in pts)
lons = ",".join(f"{p[1]:.2f}" for p in pts)
url = (f"https://api.open-meteo.com/v1/forecast?latitude={lats}&longitude={lons}"
       f"&hourly=precipitation&forecast_days=2&timezone=UTC")
status, body, elapsed = get(url)
print(f"  grid points: {len(pts)}")
print(f"  HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    data = json.loads(body)
    arr = data if isinstance(data, list) else [data]
    totals = []
    for d in arr:
        precip = d.get("hourly", {}).get("precipitation", [])
        if precip:
            total = sum(p or 0 for p in precip)
            totals.append((d.get("latitude"), d.get("longitude"), total))
    wet = [t for t in totals if t[2] >= 0.1]
    print(f"  wet cells (>=0.1mm): {len(wet)} / {len(totals)}")
    if wet:
        wet_sorted = sorted(wet, key=lambda t: -t[2])
        print(f"  top 3 wettest 48h forecast:")
        for lat, lon, mm in wet_sorted[:3]:
            print(f"    lat={lat:.1f} lon={lon:.1f}  {mm:.1f} mm")

print()
print("=" * 70)
print("3. SST ANOMALY  -  Open-Meteo Marine")
print("=" * 70)
pts = build_grid(15, 25, 60, -60)[:80]
lats = ",".join(f"{p[0]:.2f}" for p in pts)
lons = ",".join(f"{p[1]:.2f}" for p in pts)
url = (f"https://marine-api.open-meteo.com/v1/marine?latitude={lats}&longitude={lons}"
       f"&current=sea_surface_temperature&timezone=UTC")
status, body, elapsed = get(url)
print(f"  grid points: {len(pts)}")
print(f"  HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    data = json.loads(body)
    arr = data if isinstance(data, list) else [data]
    def baseline(lat):
        a = abs(lat)
        if a < 5:  return 28.5
        if a < 15: return 27.5
        if a < 25: return 25.0
        if a < 35: return 21.0
        if a < 45: return 16.0
        if a < 55: return 10.0
        return 5.0
    anomalies = []
    for d in arr:
        sst = d.get("current", {}).get("sea_surface_temperature")
        if sst is not None:
            anomalies.append((d["latitude"], d["longitude"], sst, sst - baseline(d["latitude"])))
    print(f"  cells with SST: {len(anomalies)} / {len(arr)}")
    if anomalies:
        anomalies_sorted = sorted(anomalies, key=lambda t: -abs(t[3]))
        print(f"  top 3 anomalies by magnitude:")
        for lat, lon, sst, anom in anomalies_sorted[:3]:
            sign = "+" if anom >= 0 else ""
            print(f"    lat={lat:.1f} lon={lon:.1f}  SST {sst:.1f}C  anomaly {sign}{anom:.1f}C")

print()
print("=" * 70)
print("4. NASA EONET  -  open natural events (last 7 d)")
print("=" * 70)
url = "https://eonet.gsfc.nasa.gov/api/v3/events?status=open&days=7&limit=200"
status, body, elapsed = get(url)
print(f"  HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    data = json.loads(body)
    events = data.get("events", [])
    print(f"  open events: {len(events)}")
    cats = {}
    for e in events:
        cat = (e.get("categories") or [{}])[0].get("title", "?")
        cats[cat] = cats.get(cat, 0) + 1
    for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"    {cat}: {n}")
    if events:
        e = events[0]
        geoms = e.get("geometry", [])
        latest = geoms[-1] if geoms else {}
        sources = ", ".join(s.get("id", "") for s in e.get("sources", []))
        print(f"  sample: '{e.get('title')}'")
        print(f"    category: {(e.get('categories') or [{}])[0].get('title')}")
        print(f"    coords:   {latest.get('coordinates')}  @ {latest.get('date')}")
        print(f"    tracking sources: {sources}")

print()
print("=" * 70)
print("5. GDACS  -  multi-hazard alerts")
print("=" * 70)
end = datetime.utcnow().strftime("%Y-%m-%d")
start = (datetime.utcnow() - timedelta(days=7)).strftime("%Y-%m-%d")
url = (f"https://www.gdacs.org/gdacsapi/api/events/geteventlist/MAP?"
       f"fromdate={start}&todate={end}&alertlevel=Green;Orange;Red")
status, body, elapsed = get(url)
print(f"  HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    data = json.loads(body)
    feats = data.get("features", [])
    print(f"  active alerts: {len(feats)}")
    levels, types = {}, {}
    for f in feats:
        p = f.get("properties", {})
        levels[p.get("alertlevel", "?")] = levels.get(p.get("alertlevel", "?"), 0) + 1
        types[p.get("eventtype", "?")]    = types.get(p.get("eventtype", "?"), 0) + 1
    print(f"  by level: {levels}")
    print(f"  by type:  {types}")
    if feats:
        f = feats[0]
        p = f.get("properties", {})
        c = f.get("geometry", {}).get("coordinates")
        print(f"  sample: '{p.get('name')}'  [{p.get('alertlevel')}]  {p.get('eventtype')}")
        print(f"    country: {p.get('country')}   coords: {c}")
        print(f"    dates:   {p.get('fromdate', '?')[:10]} -> {p.get('todate', '?')[:10]}")

print()
print("=" * 70)
print("6. NWS ACTIVE ALERTS  -  api.weather.gov (USA)")
print("=" * 70)
url = "https://api.weather.gov/alerts/active?status=actual"
status, body, elapsed = get(url, headers={"Accept": "application/geo+json", "User-Agent": "ecolens-map-test"})
print(f"  HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    data = json.loads(body)
    feats = data.get("features", [])
    skipped = [f for f in feats if re.search(r"Flood|Fire Weather|Tsunami|Earthquake", f.get("properties", {}).get("event", ""), re.I)]
    kept    = [f for f in feats if not re.search(r"Flood|Fire Weather|Tsunami|Earthquake", f.get("properties", {}).get("event", ""), re.I)]
    with_geom = [f for f in kept if f.get("geometry")]
    print(f"  total active alerts: {len(feats)}")
    print(f"  skipped (covered by other layers): {len(skipped)}")
    print(f"  kept after filter:    {len(kept)}")
    print(f"  renderable (have geometry): {len(with_geom)}")
    events, sevs = {}, {}
    for f in with_geom:
        p = f.get("properties", {})
        events[p.get("event", "?")] = events.get(p.get("event", "?"), 0) + 1
        sevs[p.get("severity", "?")] = sevs.get(p.get("severity", "?"), 0) + 1
    print(f"  top events:")
    for ev, n in sorted(events.items(), key=lambda x: -x[1])[:6]:
        print(f"    {ev}: {n}")
    print(f"  by severity: {sevs}")

print()
print("=" * 70)
print("7. CORRELATION SETUP  -  FIRMS hotspots (used for fire x wind)")
print("=" * 70)
url = "https://us-central1-ecolens-ad854.cloudfunctions.net/firms_proxy?days=2&sat=auto&area=world"
status, body, elapsed = get(url)
print(f"  FIRMS proxy: HTTP {status} in {elapsed:.1f}s, body {len(body)} bytes")
if status == 200:
    try:
        fc = json.loads(body)
        fires = fc.get("features", [])
        print(f"  active hotspots loaded: {len(fires)}")
        meta = fc.get("metadata", {})
        print(f"  satellite used: {meta.get('satellite', 'unknown')}")
        if fires:
            top = sorted(fires, key=lambda f: -(f.get("properties", {}).get("frp") or 0))[:3]
            print(f"  top 3 by FRP  -  these get fire-spread correlation arrows:")
            for f in top:
                p = f.get("properties", {})
                c = f.get("geometry", {}).get("coordinates", [None, None])
                print(f"    FRP={p.get('frp')} MW  lat={c[1]:.2f} lon={c[0]:.2f}  conf={p.get('confidence')}")
    except Exception as e:
        print(f"  parse error: {e}")
        print(f"  body head: {body[:200]}")
