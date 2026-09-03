import os

import requests


class FIRMSService:
    """NASA FIRMS area queries. The MAP_KEY comes from the NASA_FIRMS_MAP_KEY secret
    (bound in main.py) or the environment; it is never hardcoded."""

    def __init__(self, api_key=None):
        self.api_key = api_key or os.environ.get("NASA_FIRMS_MAP_KEY", "")
        if not self.api_key:
            raise ValueError("NASA_FIRMS_MAP_KEY is not set")

    def fetch(self, bbox):
        """
        Fetch fire data for a bounding box
        
        Args:
            bbox: Dict with keys min_lat, max_lat, min_lng, max_lng
        """
        # Check if bbox is too large (FIRMS has size limits)
        lat_range = abs(bbox['max_lat'] - bbox['min_lat'])
        lng_range = abs(bbox['max_lng'] - bbox['min_lng'])
        
        # If bbox is larger than 20 degrees, use center point
        if lat_range > 20 or lng_range > 20:
            center_lat = (bbox['min_lat'] + bbox['max_lat']) / 2
            center_lng = (bbox['min_lng'] + bbox['max_lng']) / 2
            url = f"https://firms.modaps.eosdis.nasa.gov/api/area/csv/{self.api_key}/VIIRS_SNPP_NRT/{center_lng},{center_lat},500/7"
        else:
            bbox_str = f"{bbox['min_lng']},{bbox['min_lat']},{bbox['max_lng']},{bbox['max_lat']}"
            url = f"https://firms.modaps.eosdis.nasa.gov/api/area/csv/{self.api_key}/VIIRS_SNPP_NRT/{bbox_str}/7"
        
        try:
            response = requests.get(url, timeout=30)
            response.raise_for_status()
            
            # Parse CSV
            fires = []
            lines = response.text.strip().split('\n')
            
            if len(lines) > 1:
                headers = lines[0].split(',')
                for line in lines[1:]:
                    values = line.split(',')
                    fire = dict(zip(headers, values))
                    fires.append(fire)
            
            return fires
            
        except Exception as e:
            print(f"FIRMS API error: {e}")
            return []