"""
Biodiversity Analysis Agent

Pulls REAL species data observed at the location from:
- GBIF Occurrence Search API (https://api.gbif.org/v1/occurrence/search)
- GBIF Species details
- IUCN Red List categories via GBIF (https://api.gbif.org/v1/species/{key}/iucnRedListCategory)

No Gemini, no fabrication. Species listed are documented occurrences within
~25km of the target location. Conservation status comes from IUCN Red List.
"""
import requests
from typing import Dict, Any, List, Optional

GBIF_BASE = "https://api.gbif.org/v1"
KINGDOM_ANIMALIA = 1
KINGDOM_PLANTAE = 6
SEARCH_RADIUS_DEG = 0.25  # ~25 km at equator
REQUEST_TIMEOUT = 8
AT_RISK_CODES = {'CR', 'EN', 'VU', 'NT'}

IUCN_LABELS = {
    'CR': 'Critically Endangered',
    'EN': 'Endangered',
    'VU': 'Vulnerable',
    'NT': 'Near Threatened',
    'LC': 'Least Concern',
    'DD': 'Data Deficient',
    'NE': 'Not Evaluated',
}


class BiodiversityAgent:
    def analyze(self, lat: float, lng: float, habitat: str = None,
                soil_data: Dict = None, terrain_data: Dict = None,
                hydrology_data: Dict = None) -> Dict[str, Any]:
        """
        Return species observed near (lat, lng) from GBIF, split by IUCN status.

        Args:
            lat, lng: target coordinates
            habitat, soil_data, terrain_data, hydrology_data: accepted for
                backward compatibility but unused — real biodiversity data
                comes from observed occurrences, not derived from soil/terrain.

        Returns:
            dict with fauna_at_risk / flora_at_risk / fauna_thrive / flora_thrive
        """
        try:
            polygon = self._polygon(lat, lng, SEARCH_RADIUS_DEG)

            fauna = self._top_species(polygon, KINGDOM_ANIMALIA, limit=12)
            flora = self._top_species(polygon, KINGDOM_PLANTAE, limit=12)

            fauna_at_risk, fauna_thrive = self._split_by_iucn(fauna, kind='fauna')
            flora_at_risk, flora_thrive = self._split_by_iucn(flora, kind='flora')

            return {
                'fauna_at_risk': fauna_at_risk[:8],
                'flora_at_risk': flora_at_risk[:8],
                'fauna_thrive': fauna_thrive[:8],
                'flora_thrive': flora_thrive[:8],
                'data_source': 'GBIF Occurrence Search + IUCN Red List',
                'search_radius_km': 25,
                'attribution': (
                    'GBIF.org occurrence data; IUCN Red List of Threatened Species'
                ),
                'available': True,
            }
        except Exception as e:
            print(f"❌ Biodiversity Agent Error: {e}")
            return {
                'fauna_at_risk': [],
                'flora_at_risk': [],
                'fauna_thrive': [],
                'flora_thrive': [],
                'available': False,
                'error': str(e),
            }

    @staticmethod
    def _polygon(lat: float, lng: float, half_side_deg: float) -> str:
        """Build a WKT POLYGON bounding box centered on (lat, lng)."""
        min_lat, max_lat = lat - half_side_deg, lat + half_side_deg
        min_lng, max_lng = lng - half_side_deg, lng + half_side_deg
        return (
            f"POLYGON(({min_lng} {min_lat},{max_lng} {min_lat},"
            f"{max_lng} {max_lat},{min_lng} {max_lat},"
            f"{min_lng} {min_lat}))"
        )

    def _top_species(self, polygon: str, kingdom_key: int,
                     limit: int) -> List[Dict]:
        """Query GBIF for the most-observed species in the polygon."""
        url = f"{GBIF_BASE}/occurrence/search"
        params = {
            'geometry': polygon,
            'kingdomKey': kingdom_key,
            'facet': 'speciesKey',
            'facetLimit': limit,
            'limit': 0,  # we only want facets
        }
        try:
            resp = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
            resp.raise_for_status()
            facets = resp.json().get('facets', [])
            if not facets:
                return []
            counts = facets[0].get('counts', [])
            species_keys = [int(c['name']) for c in counts if c.get('name')]
        except Exception as e:
            print(f"⚠️ GBIF facet query failed (kingdom={kingdom_key}): {e}")
            return []

        species = []
        for key in species_keys:
            details = self._species_details(key)
            if details:
                species.append(details)
        return species

    def _species_details(self, species_key: int) -> Optional[Dict]:
        """Fetch species name + IUCN status for a GBIF species key."""
        try:
            sp_resp = requests.get(
                f"{GBIF_BASE}/species/{species_key}",
                timeout=REQUEST_TIMEOUT,
            )
            if sp_resp.status_code != 200:
                return None
            sp = sp_resp.json()
            scientific = (
                sp.get('canonicalName') or sp.get('scientificName') or 'Unknown'
            )
            common = sp.get('vernacularName') or ''

            iucn_resp = requests.get(
                f"{GBIF_BASE}/species/{species_key}/iucnRedListCategory",
                timeout=REQUEST_TIMEOUT,
            )
            iucn_category = None
            if iucn_resp.status_code == 200:
                iucn_category = iucn_resp.json().get('category')

            return {
                'scientific_name': scientific,
                'common_name': common or scientific,
                'iucn_category': iucn_category,
            }
        except Exception as e:
            print(f"⚠️ GBIF species lookup failed (key={species_key}): {e}")
            return None

    def _split_by_iucn(self, species: List[Dict], kind: str):
        """Bucket species into at-risk (CR/EN/VU/NT) vs the rest."""
        at_risk = []
        thriving = []
        for sp in species:
            iucn = sp.get('iucn_category')
            base = {
                'scientific_name': sp['scientific_name'],
                'common_name': sp['common_name'],
            }
            if iucn in AT_RISK_CODES:
                threat_level = (
                    'High' if iucn in {'CR', 'EN'}
                    else ('Medium' if iucn == 'VU' else 'Low')
                )
                at_risk.append({
                    **base,
                    'status': IUCN_LABELS.get(iucn, iucn),
                    'threat_level': threat_level,
                })
            else:
                # Documented locally and not flagged at risk — treat as
                # naturally-occurring native population. We don't invent
                # roles or growth rates we can't measure.
                if kind == 'fauna':
                    thriving.append({
                        **base,
                        'role': 'Observed locally',
                        'resilience': 'Documented occurrence',
                    })
                else:
                    thriving.append({
                        **base,
                        'role': 'Observed locally',
                        'growth_rate': 'Documented occurrence',
                    })
        return at_risk, thriving
