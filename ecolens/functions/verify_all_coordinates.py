
import sys
import os

# Add current directory to path so imports work
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_full_pipeline import test_single_location

def verify_all():
    print("🚀 STARTING COMPREHENSIVE VERIFICATION FOR 3 BIOMES")
    print("="*80)

    # 1. Boreal (Canada)
    print("\n🌲 TEST CASE 1: BOREAL FOREST (Canada)")
    try:
        test_single_location(
            lat=54.9, 
            lng=-115.2, 
            region_name="Swan Hills, Alberta", 
            habitat_type="Boreal Forest"
        )
    except Exception as e:
        print(f"❌ BOREAL TEST FAILED: {e}")

    # 2. Tropical (Amazon)
    print("\n🦜 TEST CASE 2: TROPICAL RAINFOREST (Amazon)")
    try:
        test_single_location(
            lat=-3.5, 
            lng=-62.0, 
            region_name="Brazilian Amazon", 
            habitat_type="Tropical Rainforest"
        )
    except Exception as e:
        print(f"❌ TROPICAL TEST FAILED: {e}")

    # 3. Arid (Sudan)
    print("\n🌵 TEST CASE 3: ARID / SAHEL (Sudan)")
    try:
        test_single_location(
            lat=15.5, 
            lng=32.5, 
            region_name="Sudan (Sahel)", 
            habitat_type="Semi-Arid Savanna"
        )
    except Exception as e:
        print(f"❌ ARID TEST FAILED: {e}")

    print("\n" + "="*80)
    print("✅ VERIFICATION COMPLETE")

if __name__ == "__main__":
    verify_all()
