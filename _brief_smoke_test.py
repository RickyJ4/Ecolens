"""Smoke-test the Overpass impact-zone query at three locations
the EventIntelligence module would actually run on click."""
import urllib.request, json, ssl, time

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def overpass(lat, lon, radius_km):
    r = int(radius_km * 1000)
    q = f"""[out:json][timeout:25];
(
  nwr["amenity"="hospital"](around:{r},{lat},{lon});
  nwr["amenity"="clinic"](around:{r},{lat},{lon});
  nwr["amenity"="school"](around:{r},{lat},{lon});
  nwr["amenity"="fire_station"](around:{r},{lat},{lon});
  nwr["power"="plant"](around:{r},{lat},{lon});
  node["place"~"^(city|town|village|hamlet|suburb)$"](around:{r},{lat},{lon});
);
out tags center 3000;"""
    req = urllib.request.Request(
        "https://overpass-api.de/api/interpreter",
        data=q.encode(),
        headers={"Content-Type": "text/plain", "User-Agent": "ecolens-test"},
        method="POST",
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
            data = json.loads(r.read())
            return data, time.time() - t0
    except Exception as e:
        return None, time.time() - t0, str(e)


def parse(elements):
    res = {"hospitals":0,"clinics":0,"schools":0,"fire_stations":0,"power":0,"places":[]}
    for el in elements:
        t = el.get("tags", {})
        a = t.get("amenity")
        if a == "hospital": res["hospitals"] += 1
        elif a == "clinic": res["clinics"] += 1
        elif a == "school": res["schools"] += 1
        elif a == "fire_station": res["fire_stations"] += 1
        elif t.get("power") == "plant": res["power"] += 1
        elif t.get("place"):
            pop = 0
            try: pop = int(t.get("population", "0"))
            except: pass
            res["places"].append({
                "name": t.get("name", "(unnamed)"),
                "type": t.get("place"),
                "pop": pop,
            })
    res["places"].sort(key=lambda p: -p["pop"])
    res["pop_sum"] = sum(p["pop"] for p in res["places"])
    res["places_tagged"] = sum(1 for p in res["places"] if p["pop"] > 0)
    return res


cases = [
    ("DRC fire — North Kivu",      -1.41, 29.20, 35),
    ("Boris cyclone — Mexico",     15.4, -99.1, 60),
    ("Florida flood corridor",     27.99, -82.46, 25),  # Tampa Bay
]

for label, lat, lon, radius in cases:
    print("=" * 70)
    print(f"{label}   lat={lat}  lon={lon}  radius={radius} km")
    print("=" * 70)
    res = overpass(lat, lon, radius)
    if res[0] is None:
        print(f"  FAILED in {res[1]:.1f}s: {res[2] if len(res) > 2 else 'no data'}")
        continue
    data, elapsed = res
    elements = data.get("elements", [])
    print(f"  Overpass returned {len(elements)} elements in {elapsed:.1f}s")
    parsed = parse(elements)
    print(f"  hospitals={parsed['hospitals']}  clinics={parsed['clinics']}  "
          f"schools={parsed['schools']}  fire={parsed['fire_stations']}  power={parsed['power']}")
    print(f"  settlements: {len(parsed['places'])}  with population tag: {parsed['places_tagged']}")
    print(f"  total tagged population: {parsed['pop_sum']:,}")
    print(f"  top 5 settlements:")
    for p in parsed["places"][:5]:
        pop_str = f"{p['pop']:,}" if p["pop"] > 0 else "—"
        print(f"    {p['type']:8s}  {p['name'][:40]:40s}  {pop_str}")
    print()
