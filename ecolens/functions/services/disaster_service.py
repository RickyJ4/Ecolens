import requests
from datetime import datetime

class DisasterService:
    USGS_FEED_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_day.geojson"

    def fetch_earthquakes(self):
        response = requests.get(self.USGS_FEED_URL, timeout=30)
        response.raise_for_status()
        return response.json()

    def earthquakes_near_point(self, point, max_distance_km=100):
        """
        Filters earthquakes near a point
        """
        data = self.fetch_earthquakes()
        nearby = []

        for feature in data["features"]:
            coords = feature["geometry"]["coordinates"]
            quake_point = (coords[1], coords[0])

            from utils.geo_utils import distance_km
            distance = distance_km(point, quake_point)

            if distance <= max_distance_km:
                nearby.append({
                    "magnitude": feature["properties"]["mag"],
                    "place": feature["properties"]["place"],
                    "distance_km": round(distance, 2),
                    "time": datetime.utcfromtimestamp(
                        feature["properties"]["time"] / 1000
                    ).isoformat()
                })

        return nearby
