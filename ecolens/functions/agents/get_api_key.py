# test_gfw_agent.py
from gfw_ingestion_agent import GFWIngestionAgent
import json

agent = GFWIngestionAgent()

print("Testing EcoLens GFW Ingestion Agent - FIXED VERSION")
print("=" * 70)

try:
    hotspots = agent.fetch_global_alerts()
    print(f"\n✅ SUCCESS: Discovered {len(hotspots)} deforestation hotspots")
    
    if hotspots:
        print(f"\n📍 Sample hotspot:")
        print(json.dumps(hotspots[0], indent=2, default=str))
        
except Exception as e:
    print(f"❌ Error: {e}")
    import traceback
    traceback.print_exc()