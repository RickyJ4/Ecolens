"""
Test pipeline with user's actual coordinates from app
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# User's actual coordinates from the app
TEST_LAT = -7.5
TEST_LNG = -45.2

def test_pipeline():
    print("=" * 70)
    print(f"🧪 Testing with USER'S COORDINATES: {TEST_LAT}, {TEST_LNG}")
    print("=" * 70)
    
    try:
        from orchestrator.intelligence_pipeline import IntelligencePipeline
        pipeline = IntelligencePipeline()
        
        print("\n🚀 Running analyze_location...")
        result = pipeline.analyze_location(TEST_LAT, TEST_LNG, "Amazon Basin")
        
        print("\n" + "=" * 70)
        print("📊 RESULTS SUMMARY")
        print("=" * 70)
        
        # Check each layer
        layers = [
            ('soil_analysis', '🌱 Soil'),
            ('terrain_analysis', '🏔️ Terrain'),
            ('hydrology_analysis', '💧 Hydrology'),
            ('historical_analysis', '📈 Historical'),
            ('recovery_potential', '🔢 Recovery'),
            ('comprehensive_analysis', '🧠 Comprehensive'),
        ]
        
        for key, label in layers:
            data = result.get(key, {})
            if data:
                print(f"\n{label}: ✅ HAS DATA")
                # Show key values
                if key == 'soil_analysis':
                    ph = data.get('ph', {})
                    print(f"   pH: {ph.get('value', 'N/A')}")
                    print(f"   Texture: {data.get('soil_texture', {}).get('class', 'N/A')}")
                elif key == 'terrain_analysis':
                    elev = data.get('elevation', {})
                    slope = data.get('slope', {})
                    print(f"   Elevation: {elev.get('min_m', 'N/A')}-{elev.get('max_m', 'N/A')}m")
                    print(f"   Slope: {slope.get('mean_degrees', 'N/A')}°")
                elif key == 'hydrology_analysis':
                    access = data.get('water_accessibility', {})
                    print(f"   Rating: {access.get('rating', 'N/A')}")
                    print(f"   Features: {data.get('water_features', {}).get('count', 0)}")
                elif key == 'historical_analysis':
                    summary = data.get('summary', {})
                    print(f"   Years: {summary.get('year_range', 'N/A')}")
                    print(f"   Total Loss: {summary.get('total_loss_ha', 'N/A')} ha")
                elif key == 'recovery_potential':
                    print(f"   Score: {data.get('score', 'N/A')}")
                elif key == 'comprehensive_analysis':
                    print(f"   Success: {data.get('success_probability', 'N/A')}")
            else:
                print(f"\n{label}: ❌ EMPTY")
        
        # Save full output
        output_path = os.path.join(os.path.dirname(__file__), 'test_user_coords.json')
        with open(output_path, 'w') as f:
            json.dump(result, f, indent=2, default=str)
        print(f"\n📁 Full output: {output_path}")
        
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
