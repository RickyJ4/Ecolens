"""Fetch WRI Global Power Plant Database CSV and convert to slim JSON
for cross-validation in event-intelligence.js.

Source: WRI Global Power Plant Database, v1.3.0 (2021), CC BY 4.0.
GitHub mirror at https://github.com/wri/global-power-plant-database

Output keeps only the fields we need for spatial cross-validation:
  name, lat, lon, country, capacity_mw, fuel

Result is bundled at:
  ecolens/web/assets/wri_power_plants.json
which Firebase Hosting serves at /assets/wri_power_plants.json after deploy.
"""
import urllib.request, csv, json, ssl, io, sys, os

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

URL = "https://raw.githubusercontent.com/wri/global-power-plant-database/master/output_database/global_power_plant_database.csv"
OUT = r"c:\Users\User\Desktop\EcoLens\ecolens\web\assets\wri_power_plants.json"

print(f"Fetching {URL}")
req = urllib.request.Request(URL, headers={"User-Agent": "ecolens-build/1.0"})
with urllib.request.urlopen(req, context=ctx, timeout=60) as r:
    raw = r.read().decode("utf-8", errors="replace")

print(f"Got {len(raw):,} bytes")
reader = csv.DictReader(io.StringIO(raw))

plants = []
skipped = 0
for row in reader:
    try:
        lat = float(row["latitude"])
        lon = float(row["longitude"])
    except (KeyError, ValueError):
        skipped += 1
        continue
    try:
        cap = float(row.get("capacity_mw", "") or 0)
    except ValueError:
        cap = 0
    plants.append({
        "name": row.get("name", "").strip(),
        "lat": round(lat, 5),
        "lon": round(lon, 5),
        "country": row.get("country", "").strip(),
        "capacity_mw": round(cap, 1),
        "fuel": (row.get("primary_fuel", "") or "").strip(),
    })

print(f"Parsed {len(plants):,} plants (skipped {skipped} without coords)")

# Ensure output directory exists
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(plants, f, separators=(",", ":"))
size_mb = os.path.getsize(OUT) / 1024 / 1024
print(f"Wrote {OUT} ({size_mb:.1f} MB)")

# Sanity check the DRC region (Goma area)
goma_lat, goma_lon = -1.41, 29.20
def hav(la1, lo1, la2, lo2):
    from math import radians, sin, cos, sqrt, atan2
    R = 6371
    dla = radians(la2 - la1); dlo = radians(lo2 - lo1)
    a = sin(dla/2)**2 + cos(radians(la1))*cos(radians(la2))*sin(dlo/2)**2
    return 2*R*atan2(sqrt(a), sqrt(1-a))

nearby = [(p, hav(goma_lat, goma_lon, p["lat"], p["lon"])) for p in plants]
nearby_35 = [p for p, d in nearby if d <= 35]
nearby_100 = [p for p, d in nearby if d <= 100]
print(f"\nSanity check around -1.41, 29.20 (Goma area):")
print(f"  Within 35 km:  {len(nearby_35)} plants")
print(f"  Within 100 km: {len(nearby_100)} plants")
for p in nearby_35[:5]:
    print(f"    {p['name']:40s} {p['capacity_mw']:>8} MW  {p['fuel']}")
