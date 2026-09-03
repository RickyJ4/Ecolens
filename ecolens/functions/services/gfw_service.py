import os

import requests


class GFWService:
    BASE_URL = "https://data-api.globalforestwatch.org"

    def __init__(self, api_key=None):
        api_key = api_key or os.environ.get("GFW_API_KEY", "")
        if not api_key:
            raise ValueError("GFW_API_KEY is not set")
        self.headers = {
            "x-api-key": api_key,  # Changed from "Authorization: Bearer"
            "Content-Type": "application/json",
        }

    def list_datasets(self):
        """
        List available datasets to verify correct dataset names
        """
        response = requests.get(
            f"{self.BASE_URL}/dataset",
            headers=self.headers,
            timeout=30,
        )
        response.raise_for_status()
        return response.json()

    def fetch_tree_loss(
        self,
        aoi_geojson: dict,
        start_date: str,
        end_date: str,
    ):
        """
        Fetch Hansen (UMD) tree cover loss for a given AOI and date range
        """
        # Extract geometry
        geometry = (
            aoi_geojson.get("geometry")
            if isinstance(aoi_geojson, dict) and "geometry" in aoi_geojson
            else aoi_geojson
        )

        # Step 1: Create a geostore for the AOI
        try:
            geostore_response = requests.post(
                f"{self.BASE_URL}/geostore",
                headers=self.headers,
                json={"geojson": geometry},
                timeout=30,
            )
            geostore_response.raise_for_status()
            geostore_id = geostore_response.json()["data"]["id"]
        except requests.exceptions.HTTPError as e:
            print(f"Error creating geostore: {e}")
            raise

        # Step 2: Query tree cover loss using SQL
        # Parse years from date strings (e.g., "2020-01-01" -> 2020)
        start_year = int(start_date.split("-")[0])
        end_year = int(end_date.split("-")[0])

        sql_query = f"""
            SELECT * FROM data 
            WHERE umd_tree_cover_loss__year >= {start_year} 
            AND umd_tree_cover_loss__year <= {end_year}
        """

        try:
            response = requests.get(
                f"{self.BASE_URL}/dataset/umd_tree_cover_loss/latest/query/json",
                headers=self.headers,
                params={
                    "sql": sql_query,
                    "geostore_id": geostore_id
                },
                timeout=30,
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 404:
                print("Dataset not found. Available datasets:")
                datasets = self.list_datasets()
                print(datasets)
                raise Exception("umd_tree_cover_loss dataset not found. Check available datasets above.")
            raise