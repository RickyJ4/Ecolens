import os

import requests
from datetime import datetime, timedelta


class GFWIngestionAgent:
    BASE_URL = "https://data-api.globalforestwatch.org"

    def __init__(self, api_key=None):
        api_key = api_key or os.environ.get("GFW_API_KEY", "")
        if not api_key:
            raise ValueError("GFW_API_KEY is not set (bind the secret in main.py or export it).")
        
        self.headers = {
            "x-api-key": api_key,
            "Content-Type": "application/json",
        }

    # ═════════════════════════════════════════════════════════════
    # GLOBAL HOTSPOT DISCOVERY - WORKING VERSION
    # ═════════════════════════════════════════════════════════════
    
    def fetch_global_alerts(self):
        """
        Main method: Autonomous global hotspot discovery
        
        Uses regional scanning since GFW datasets require geometry
        Returns emerging hotspots from high-priority forest regions
        """
        print("📡 Scanning global deforestation hotspots...")
        return self.fetch_emerging_hotspots_by_region()
    
    def fetch_emerging_hotspots_by_region(self):
        """
        Query emerging hotspots across major forest regions
        
        This works because:
        - Uses /query endpoint (not /download)
        - Provides required SQL and geometry
        - Queries manageable regions to avoid timeouts
        """
        
        # Major forest regions
        forest_regions = {
            "amazon_west": {
                "name": "Western Amazon",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [-75, -15], [-60, -15], [-60, 0], [-75, 0], [-75, -15]
                    ]]
                }
            },
            "amazon_east": {
                "name": "Eastern Amazon",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [-60, -15], [-45, -15], [-45, 5], [-60, 5], [-60, -15]
                    ]]
                }
            },
            "congo": {
                "name": "Congo Basin",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [12, -8], [30, -8], [30, 8], [12, 8], [12, -8]
                    ]]
                }
            },
            "borneo": {
                "name": "Borneo",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [109, -4], [119, -4], [119, 7], [109, 7], [109, -4]
                    ]]
                }
            },
            "sumatra": {
                "name": "Sumatra",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [95, -6], [106, -6], [106, 6], [95, 6], [95, -6]
                    ]]
                }
            },
            # North America
            "british_columbia": {
                "name": "British Columbia, Canada",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [-139, 48], [-114, 48], [-114, 60], [-139, 60], [-139, 48]
                    ]]
                }
            },
            "pacific_northwest": {
                "name": "Pacific Northwest USA",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [-125, 42], [-116, 42], [-116, 49], [-125, 49], [-125, 42]
                    ]]
                }
            },
            # Central America
            "central_america": {
                "name": "Central America",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [-92, 7], [-77, 7], [-77, 23], [-92, 23], [-92, 7]
                    ]]
                }
            },
            # East Africa
            "east_africa": {
                "name": "East Africa",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [28, -12], [42, -12], [42, 5], [28, 5], [28, -12]
                    ]]
                }
            },
            # Australia
            "australia_east": {
                "name": "Eastern Australia",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [145, -40], [154, -40], [154, -10], [145, -10], [145, -40]
                    ]]
                }
            },
        }
        
        all_hotspots = []
        successful_regions = 0
        
        for region_id, region_data in forest_regions.items():
            try:
                print(f"  → {region_data['name']}...", end=" ", flush=True)
                
                # Query emerging hotspots for this region
                sql = "SELECT * FROM results LIMIT 500"
                
                response = requests.post(
                    f"{self.BASE_URL}/dataset/gfw_emerging_hot_spots/v2024/query/json",
                    headers=self.headers,
                    json={
                        "sql": sql,
                        "geometry": region_data["geometry"]
                    },
                    timeout=60,
                )
                
                response.raise_for_status()
                data = response.json()
                hotspots = data.get("data", [])
                
                # Add region context
                for hotspot in hotspots:
                    hotspot["region"] = region_data["name"]
                    hotspot["region_id"] = region_id
                    hotspot["discovered_at"] = datetime.utcnow().isoformat()
                    hotspot["source"] = "gfw_emerging_hot_spots"
                
                all_hotspots.extend(hotspots)
                successful_regions += 1
                print(f"✅ {len(hotspots)} hotspots")
                
            except Exception as e:
                print(f"⚠️ {str(e)[:60]}")
                continue
        
        print(f"\n✅ Scan complete: {len(all_hotspots)} total hotspots from {successful_regions}/{len(forest_regions)} regions")
        return all_hotspots

    # ═════════════════════════════════════════════════════════════
    # FIRE ALERTS (Alternative/Complementary Data)
    # ═════════════════════════════════════════════════════════════
    
    def fetch_fire_alerts_by_region(self, days: int = 7):
        """
        Fetch recent fire alerts as complement to deforestation data
        """
        since = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%d")
        
        print(f"📡 Scanning fire alerts since {since}...")
        
        # Smaller regions to avoid timeouts
        regions = {
            "amazon_rondonia": {
                "name": "Amazon Rondônia",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [-65, -13], [-60, -13], [-60, -8], [-65, -8], [-65, -13]
                    ]]
                }
            },
            "borneo_central": {
                "name": "Central Borneo",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [112, -2], [117, -2], [117, 2], [112, 2], [112, -2]
                    ]]
                }
            },
        }
        
        all_fires = []
        
        for region_id, region_data in regions.items():
            try:
                print(f"  → {region_data['name']}...", end=" ", flush=True)
                
                # Check fields first to get correct field names
                fields_response = requests.get(
                    f"{self.BASE_URL}/dataset/nasa_viirs_fire_alerts/latest/fields",
                    headers=self.headers,
                    timeout=30,
                )
                
                if fields_response.status_code == 200:
                    fields_data = fields_response.json()
                    field_names = [f['name'] for f in fields_data.get('data', [])]
                    
                    # Build SQL with actual field names
                    sql = f"SELECT * FROM results LIMIT 200"
                    
                    response = requests.post(
                        f"{self.BASE_URL}/dataset/nasa_viirs_fire_alerts/latest/query/json",
                        headers=self.headers,
                        json={
                            "sql": sql,
                            "geometry": region_data["geometry"]
                        },
                        timeout=60,
                    )
                    
                    if response.status_code == 200:
                        data = response.json()
                        fires = data.get("data", [])
                        
                        for fire in fires:
                            fire["region"] = region_data["name"]
                            fire["region_id"] = region_id
                        
                        all_fires.extend(fires)
                        print(f"✅ {len(fires)} fires")
                    else:
                        print(f"⚠️ Status {response.status_code}")
                else:
                    print("⚠️ Can't get fields")
                    
            except Exception as e:
                print(f"⚠️ {str(e)[:60]}")
                continue
        
        print(f"✅ Total: {len(all_fires)} fire alerts")
        return all_fires

    # ═════════════════════════════════════════════════════════════
    # AOI-SPECIFIC QUERIES
    # ═════════════════════════════════════════════════════════════
    
    def fetch_alerts_for_aoi(self, aoi_geojson: dict, dataset: str = "gfw_emerging_hot_spots"):
        """
        Fetch alerts for a specific community-reported area
        """
        geometry = (
            aoi_geojson.get("geometry")
            if isinstance(aoi_geojson, dict) and "geometry" in aoi_geojson
            else aoi_geojson
        )
        
        sql = "SELECT * FROM results LIMIT 1000"
        
        response = requests.post(
            f"{self.BASE_URL}/dataset/{dataset}/latest/query/json",
            headers=self.headers,
            json={"sql": sql, "geometry": geometry},
            timeout=60,
        )
        
        response.raise_for_status()
        return response.json().get("data", [])

    # ═════════════════════════════════════════════════════════════
    # UTILITY METHODS
    # ═════════════════════════════════════════════════════════════
    
    def list_datasets(self, page_number: int = 1, page_size: int = 100):
        response = requests.get(
            f"{self.BASE_URL}/datasets",
            headers=self.headers,
            params={"page[number]": page_number, "page[size]": page_size},
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def get_dataset_info(self, dataset: str):
        response = requests.get(
            f"{self.BASE_URL}/dataset/{dataset}",
            headers=self.headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def get_dataset_fields(self, dataset: str, version: str = "latest"):
        response = requests.get(
            f"{self.BASE_URL}/dataset/{dataset}/{version}/fields",
            headers=self.headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()
    def fetch_tree_loss_summary(self, aoi_geojson, start_year=2022, end_year=2025):
        """
        Fetch tree cover loss summary for an area
        Used by Analysis Agent for context
        """
        geometry = (
            aoi_geojson.get("geometry")
            if isinstance(aoi_geojson, dict) and "geometry" in aoi_geojson
            else aoi_geojson
        )

        sql = f"""
            SELECT 
                SUM(umd_tree_cover_loss__ha) as total_loss_ha,
                umd_tree_cover_loss__year
            FROM results 
            WHERE umd_tree_cover_loss__year >= {start_year} 
            AND umd_tree_cover_loss__year <= {end_year}
            GROUP BY umd_tree_cover_loss__year
            ORDER BY umd_tree_cover_loss__year
        """

        try:
            response = requests.post(
                f"{self.BASE_URL}/dataset/umd_tree_cover_loss/latest/query/json",
                headers=self.headers,
                json={"sql": sql, "geometry": geometry},
                timeout=30,
            )
            response.raise_for_status()
            return response.json().get("data", [])
        except:
            return []