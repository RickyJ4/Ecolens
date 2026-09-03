"""
Debug script to test SoilGrids API response structure
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import requests
import json

# Test with Boreal Canada coordinates
lat = 54.9
lng = -115.2

url = "https://rest.isric.org/soilgrids/v2.0/properties/query"

print("🪨 Testing SoilGrids API directly...")
print(f"📍 Coordinates: {lat}, {lng}")
print("-" * 50)

params = {
    'lon': lng,
    'lat': lat,
    'property': 'phh2o',
    'depth': '0-30cm',
    'value': 'mean'
}

try:
    print(f"📡 Fetching phh2o property...")
    response = requests.get(url, params=params, timeout=90)
    print(f"✅ Status: {response.status_code}")
    
    if response.status_code == 200:
        data = response.json()
        print(f"\n📊 Full response structure:")
        print(json.dumps(data, indent=2))
        
        # Try to extract value
        print("\n🔍 Attempting extraction...")
        layers = data.get('properties', {}).get('layers', [])
        print(f"   Layers found: {len(layers)}")
        
        if layers:
            layer = layers[0]
            print(f"   Layer name: {layer.get('name')}")
            print(f"   Unit: {layer.get('unit_measure', {}).get('mapped_units')}")
            
            depths = layer.get('depths', [])
            print(f"   Depths found: {len(depths)}")
            
            if depths:
                depth = depths[0]
                print(f"   Depth range: {depth.get('range', {})}")
                
                values = depth.get('values', {})
                print(f"   Values: {values}")
                
                mean_val = values.get('mean')
                print(f"\n✅ Extracted mean value: {mean_val}")
                
                if mean_val:
                    ph = mean_val / 10.0
                    print(f"✅ Converted pH: {ph}")
    else:
        print(f"❌ Error: {response.text}")
        
except Exception as e:
    print(f"❌ Exception: {e}")
    import traceback
    traceback.print_exc()
