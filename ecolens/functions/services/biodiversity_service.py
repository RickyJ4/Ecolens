import os

import requests


class BiodiversityService:
    """
    Fetches real biodiversity data from public APIs
    
    Data sources:
    - GBIF (Global Biodiversity Information Facility)
    - IUCN Red List API
    - Protected Planet (WDPA)
    """
    
    def __init__(self):
        self.gbif_base = "https://api.gbif.org/v1"
        self.iucn_base = "https://apiv3.iucnredlist.org/api/v3"
        # IUCN token from the IUCN_API_TOKEN secret (bound in main.py) or the environment.
        # Empty means the IUCN lookups are skipped; GBIF needs no token.
        self.iucn_token = os.environ.get("IUCN_API_TOKEN", "")
    
    def get_species_for_region(self, lat, lng, radius_km=50):
        """
        Get species observations near a location from GBIF
        
        Args:
            lat: Latitude
            lng: Longitude
            radius_km: Search radius in kilometers
        
        Returns:
            List of species with conservation status
        """
        try:
            # Calculate bounding box for GBIF search
            # approx 1 degree lat = 111km
            lat_delta = radius_km / 111.0
            # approx 1 degree lng = 111km * cos(lat)
            import math
            lng_delta = radius_km / (111.0 * math.cos(math.radians(lat)))
            
            min_lat, max_lat = lat - lat_delta, lat + lat_delta
            min_lng, max_lng = lng - lng_delta, lng + lng_delta
            
            # search GBIF using coordinate ranges
            params = {
                "decimalLatitude": f"{min_lat},{max_lat}",
                "decimalLongitude": f"{min_lng},{max_lng}",
                "limit": 100,
                "hasCoordinate": "true",
                "hasGeospatialIssue": "false"
            }
            
            response = requests.get(
                f"{self.gbif_base}/occurrence/search",
                params=params,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                species_list = self._process_gbif_data(data)
                return species_list
            
            return []
            
        except Exception as e:
            print(f"Error fetching species data: {e}")
            return []
    
    def _process_gbif_data(self, data):
        """Process GBIF API response into species list with IUCN status"""
        species = []
        seen_species = set()
        
        for result in data.get('results', []):
            scientific_name = result.get('scientificName')
            
            if not scientific_name or scientific_name in seen_species:
                continue
            
            seen_species.add(scientific_name)
            
            # Get IUCN conservation status
            iucn_status, risk_level = self._get_iucn_status(scientific_name)
            
            species_info = {
                "species": scientific_name,
                "common_name": result.get('vernacularName', 'Unknown'),
                "kingdom": result.get('kingdom', 'Unknown'),
                "class": result.get('class', 'Unknown'),
                "order": result.get('order', 'Unknown'),
                "family": result.get('family', 'Unknown'),
                "iucn_status": iucn_status,
                "risk_level": risk_level,
                "occurrence_count": 1
            }
            
            species.append(species_info)
        
        return species[:20]  # Return top 20 species
    
    def _get_iucn_status(self, scientific_name):
        """
        Get IUCN Red List status for a species
        
        Returns:
            tuple: (status_code, risk_level)
        """
        if not self.iucn_token:
            return ("Unknown", "unknown")
        
        try:
            # Clean species name (IUCN API is sensitive to formatting)
            clean_name = scientific_name.split()[0:2]  # Genus + species only
            if len(clean_name) < 2:
                return ("Unknown", "unknown")
            
            search_name = " ".join(clean_name)
            
            # Query IUCN API
            response = requests.get(
                f"{self.iucn_base}/species/{search_name}",
                params={"token": self.iucn_token},
                timeout=10
            )
            
            if response.status_code == 200:
                result = response.json()
                
                if result.get('result') and len(result['result']) > 0:
                    category = result['result'][0].get('category', 'Unknown')
                    
                    # Map IUCN category to risk level
                    risk_mapping = {
                        "CR": ("Critically Endangered", "critical"),
                        "EN": ("Endangered", "high"),
                        "VU": ("Vulnerable", "medium-high"),
                        "NT": ("Near Threatened", "medium"),
                        "LC": ("Least Concern", "low"),
                        "DD": ("Data Deficient", "unknown"),
                        "EX": ("Extinct", "extinct"),
                        "EW": ("Extinct in Wild", "critical")
                    }
                    
                    if category in risk_mapping:
                        return risk_mapping[category]
                    else:
                        return (category, "unknown")
            
            return ("Not Assessed", "unknown")
            
        except Exception as e:
            print(f"IUCN API error for {scientific_name}: {e}")
            return ("Unknown", "unknown")
    
    def get_protected_areas(self, lat, lng, radius_km=50):
        """
        Get nearby protected areas from Protected Planet API
        
        Returns list of protected areas with details
        """
        # Note: Protected Planet API requires authentication
        # For now, return structure for when implemented
        return {
            "nearby_protected_areas": [],
            "note": "Protected Planet API integration pending"
        }
    
    def get_ecosystem_services(self, habitat_type):
        """
        Get ecosystem services information for habitat type
        
        Returns:
            Dict with ecosystem services and their values
        """
        services = {
            "Tropical Rainforest": {
                "carbon_storage": "150-200 billion tons globally",
                "water_regulation": "Generates rainfall for continental regions",
                "biodiversity": "Home to 50% of terrestrial species",
                "medicine": "Source of 25% of modern medicines",
                "climate_regulation": "Major influence on global weather patterns"
            },
            "Central African Rainforest": {
                "carbon_storage": "Second largest carbon sink globally",
                "water_regulation": "Regulates Congo River basin",
                "biodiversity": "High endemism rate",
                "livelihoods": "Supports 75 million people"
            },
            "Southeast Asian Rainforest": {
                "carbon_storage": "Critical peatland carbon stores",
                "biodiversity": "Highest biodiversity per hectare",
                "water_regulation": "Monsoon regulation",
                "endemic_species": "Many species found nowhere else"
            },
            "Temperate Rainforest": {
                "carbon_storage": "Highest carbon density of any forest type",
                "water_regulation": "Critical watershed protection",
                "biodiversity": "Unique endemic species (salmon, bears)",
                "salmon_habitat": "Essential for Pacific salmon lifecycle",
                "climate_regulation": "Coastal fog and rainfall patterns"
            },
            "Pacific Temperate Forest": {
                "carbon_storage": "Significant old-growth carbon stores",
                "water_regulation": "Major watershed for Pacific Northwest",
                "biodiversity": "Spotted owl, marbled murrelet habitat",
                "timber": "Sustainable forestry potential"
            },
            "Central American Rainforest": {
                "biodiversity": "Biological corridor between continents",
                "water_regulation": "Caribbean and Pacific watershed",
                "endemic_species": "High bird and amphibian endemism",
                "livelihoods": "Indigenous community dependence"
            },
            "East African Montane Forest": {
                "water_regulation": "Source of the Nile and major African rivers",
                "biodiversity": "Mountain gorilla habitat",
                "climate_regulation": "Regional rainfall patterns",
                "agriculture": "Support for downstream farming"
            },
            "Australian Eucalyptus Forest": {
                "biodiversity": "Unique marsupial habitat",
                "fire_adaptation": "Fire-dependent ecosystem",
                "water_regulation": "Murray-Darling basin",
                "koala_habitat": "Critical for koala populations"
            },
            "Boreal Forest": {
                "carbon_storage": "Second largest carbon sink after tropical forests",
                "water_regulation": "Major freshwater source",
                "biodiversity": "Caribou, moose, wolf habitat",
                "climate_regulation": "Global climate cooling effect"
            }
        }
        
        return services.get(habitat_type, {
            "note": "Ecosystem services data not available for this habitat type"
        })