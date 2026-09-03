# debug_dataset_structure.py
from gfw_ingestion_agent import GFWIngestionAgent

agent = GFWIngestionAgent()

print("Debugging GFW Dataset Structures")
print("=" * 60)

# Check field names for each dataset
datasets_to_check = [
    "gfw_emerging_hot_spots",
    "nasa_viirs_fire_alerts",
    "umd_tree_cover_loss"
]

for dataset in datasets_to_check:
    print(f"\n📋 {dataset}")
    print("-" * 60)
    try:
        fields = agent.get_dataset_fields(dataset)
        print("Available fields:")
        for field in fields.get("data", []):
            field_name = field.get("name") or field.get("pixel_meaning")
            field_type = field.get("data_type") or field.get("type")
            print(f"  - {field_name} ({field_type})")
    except Exception as e:
        print(f"❌ Error: {e}")

print("\n" + "=" * 60)
print("\nTrying simplified download approach...")

# Try the simplest possible download
try:
    print("\nAttempting emerging hotspots download...")
    import requests
    
    response = requests.get(
        "https://data-api.globalforestwatch.org/dataset/gfw_emerging_hot_spots/latest/download/json",
        headers=agent.headers,
        params={"limit": 100},  # Try with limit parameter
        timeout=60,
    )
    
    print(f"Status: {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Success! Got {len(data.get('data', []))} records")
        if data.get('data'):
            print("\nSample record:")
            import json
            print(json.dumps(data['data'][0], indent=2))
    else:
        print(f"Response: {response.text[:300]}")
        
except Exception as e:
    print(f"❌ Error: {e}")