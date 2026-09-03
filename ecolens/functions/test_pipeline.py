"""
Test script to verify IntelligencePipeline.analyze_location returns 
soil, terrain, and hydrology data correctly.
"""
import sys
import os
import json

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Test coordinates (Vancouver, BC area)
TEST_LAT = 49.2286446
TEST_LNG = -122.9147249

def test_pipeline():
    print("=" * 70)
    print("🧪 Testing IntelligencePipeline.analyze_location()")
    print("=" * 70)
    print(f"Test Coordinates: {TEST_LAT}, {TEST_LNG}")
    print("=" * 70)
    
    try:
        from orchestrator.intelligence_pipeline import IntelligencePipeline
        pipeline = IntelligencePipeline()
        
        print("\n🚀 Running analyze_location...")
        result = pipeline.analyze_location(TEST_LAT, TEST_LNG, "Test Location")
        
        print("\n" + "=" * 70)
        print("📊 RESULTS")
        print("=" * 70)
        
        # Check each layer
        layers = [
            ('soil_analysis', '🌱 Layer 9: Soil Analysis'),
            ('terrain_analysis', '🏔️ Layer 10: Terrain Analysis'),
            ('hydrology_analysis', '💧 Layer 11: Hydrology Analysis'),
            ('historical_analysis', '📈 Layer 12: Historical Analysis'),
            ('recovery_potential', '🔢 Recovery Potential'),
            ('comprehensive_analysis', '🧠 Comprehensive Analysis'),
        ]
        
        for key, label in layers:
            data = result.get(key, {})
            status = "✅ HAS DATA" if data else "❌ EMPTY/MISSING"
            print(f"\n{label}: {status}")
            if data:
                # Print summary of data
                print(f"   Keys: {list(data.keys()) if isinstance(data, dict) else data}")
            else:
                print(f"   ⚠️ This layer returned no data!")
        
        # Save full output for debugging
        output_path = os.path.join(os.path.dirname(__file__), 'test_pipeline_output.json')
        with open(output_path, 'w') as f:
            json.dump(result, f, indent=2, default=str)
        print(f"\n📁 Full output saved to: {output_path}")
        
        print("\n" + "=" * 70)
        print("✅ Test Complete")
        print("=" * 70)
        
        return result
        
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    test_pipeline()
