"""
Terrain Analysis Agent - Layer 10

Uses Open-Elevation API to analyze terrain characteristics
for restoration suitability assessment.

API Base: https://api.open-elevation.com/api/v1/lookup
Authentication: None required (free)
"""

import requests
import time
import math
import numpy as np


class TerrainAnalysisAgent:
    """
    Analyzes terrain characteristics using Open-Elevation API
    
    Provides:
    - Elevation statistics
    - Slope calculations
    - Aspect analysis
    - Terrain difficulty assessment
    """
    
    BASE_URL = "https://api.open-elevation.com/api/v1/lookup"
    GRID_SIZE = 5  # 5x5 grid of sample points
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'EcoLens/2.0'
        })

    def analyze(self, bbox: dict) -> dict:
        """
        Main entry point - analyze terrain within bounding box
        
        Args:
            bbox: Dict with min_lat, max_lat, min_lng, max_lng
            
        Returns:
            Complete terrain analysis dict
        """
        try:
            # Create sample grid within bbox
            sample_points = self._create_sample_grid(bbox)
            
            if not sample_points:
                return self._unavailable_response("Could not create sample grid")
            
            # Fetch elevation data for all points
            elevation_data = self._fetch_elevation_data(sample_points)
            
            if not elevation_data:
                return self._unavailable_response("Elevation API returned no data")
            
            # Calculate terrain metrics
            return self._analyze_terrain(elevation_data, bbox)
            
        except Exception as e:
            print(f"❌ Terrain analysis error: {e}")
            return self._unavailable_response(str(e))

    def _create_sample_grid(self, bbox: dict) -> list:
        """
        Create NxN grid of sample points within bounding box
        """
        try:
            min_lat = float(bbox['min_lat'])
            max_lat = float(bbox['max_lat'])
            min_lng = float(bbox['min_lng'])
            max_lng = float(bbox['max_lng'])
        except (KeyError, TypeError, ValueError) as e:
            print(f"⚠️ Invalid bbox: {e}")
            return []
        
        lat_step = (max_lat - min_lat) / (self.GRID_SIZE - 1) if self.GRID_SIZE > 1 else 0
        lng_step = (max_lng - min_lng) / (self.GRID_SIZE - 1) if self.GRID_SIZE > 1 else 0
        
        points = []
        for i in range(self.GRID_SIZE):
            for j in range(self.GRID_SIZE):
                lat = min_lat + (i * lat_step)
                lng = min_lng + (j * lng_step)
                points.append({"latitude": lat, "longitude": lng})
        
        return points

    def _fetch_elevation_data(self, points: list) -> list:
        """
        Fetch elevation for all sample points using POST request
        """
        try:
            payload = {"locations": points}
            
            response = self.session.post(
                self.BASE_URL,
                json=payload,
                timeout=60
            )
            
            if response.status_code == 200:
                data = response.json()
                return data.get('results', [])
            else:
                print(f"⚠️ Open-Elevation API returned {response.status_code}")
                # Try alternative: batch single requests
                return self._fetch_elevation_fallback(points)
                
        except requests.exceptions.Timeout:
            print("⚠️ Open-Elevation API timeout, trying fallback...")
            return self._fetch_elevation_fallback(points)
        except Exception as e:
            print(f"⚠️ Elevation fetch error: {e}")
            return []

    def _fetch_elevation_fallback(self, points: list) -> list:
        """
        Fallback: Fetch elevations one at a time (slower but more reliable)
        """
        results = []
        
        for point in points[:9]:  # Limit to avoid too many requests
            try:
                params = {
                    'locations': f"{point['latitude']},{point['longitude']}"
                }
                response = self.session.get(
                    "https://api.open-elevation.com/api/v1/lookup",
                    params=params,
                    timeout=15
                )
                
                if response.status_code == 200:
                    data = response.json()
                    if data.get('results'):
                        results.append(data['results'][0])
                
                time.sleep(0.5)  # Rate limiting
                
            except Exception as e:
                print(f"⚠️ Fallback request failed: {e}")
                continue
        
        return results

    def _analyze_terrain(self, elevation_data: list, bbox: dict) -> dict:
        """
        Analyze terrain from elevation data
        """
        # Extract elevations
        elevations = []
        valid_points = []
        
        for point in elevation_data:
            elev = point.get('elevation')
            if elev is not None:
                elevations.append(elev)
                valid_points.append(point)
        
        if not elevations:
            return self._unavailable_response("No valid elevation values")
        
        # Calculate elevation statistics
        elevation_stats = self._calculate_elevation_stats(elevations)
        
        # Calculate slope (requires grid structure)
        slope_stats = self._calculate_slope(elevations, bbox)
        
        # Calculate aspect
        aspect_stats = self._calculate_aspect(elevations)
        
        # Assess slope suitability
        suitability = self._assess_slope_suitability(slope_stats['mean_degrees'])
        
        # Determine terrain ruggedness
        ruggedness = self._classify_ruggedness(elevation_stats['range_m'], slope_stats['mean_degrees'])
        
        # Generate planting recommendations
        planting_recs = self._generate_planting_recommendations(slope_stats, suitability)
        
        return {
            "available": True,
            "elevation": elevation_stats,
            "slope": {
                **slope_stats,
                "suitability": suitability
            },
            "aspect": aspect_stats,
            "terrain_ruggedness": ruggedness,
            "planting_recommendations": planting_recs,
            "cost_implications": {
                "terrain_cost_multiplier": suitability['cost_multiplier'],
                "explanation": f"{suitability['difficulty'].title()} terrain increases labor costs by ~{int((suitability['cost_multiplier'] - 1) * 100)}%"
            },
            "confidence": "medium",
            "data_source": "Open-Elevation API (SRTM 30m resolution)",
            "sample_points": len(valid_points)
        }

    def _calculate_elevation_stats(self, elevations: list) -> dict:
        """
        Calculate basic elevation statistics
        """
        return {
            "min_m": round(min(elevations), 1),
            "max_m": round(max(elevations), 1),
            "mean_m": round(sum(elevations) / len(elevations), 1),
            "range_m": round(max(elevations) - min(elevations), 1)
        }

    def _calculate_slope(self, elevations: list, bbox: dict) -> dict:
        """
        Calculate slope from elevation grid using gradient method
        
        Slope = arctan(sqrt((dz/dx)² + (dz/dy)²))
        """
        try:
            # Reshape to grid
            grid_size = int(math.sqrt(len(elevations)))
            if grid_size * grid_size != len(elevations):
                # Not a perfect square, estimate slope from elevation range
                return self._estimate_slope_from_range(elevations, bbox)
            
            dem = np.array(elevations).reshape(grid_size, grid_size)
            
            # Calculate pixel size in meters (approximate)
            lat_range = abs(float(bbox['max_lat']) - float(bbox['min_lat']))
            lng_range = abs(float(bbox['max_lng']) - float(bbox['min_lng']))
            
            # Approximate degrees to meters (varies with latitude)
            center_lat = (float(bbox['max_lat']) + float(bbox['min_lat'])) / 2
            lat_m_per_deg = 111320  # meters per degree latitude
            lng_m_per_deg = 111320 * math.cos(math.radians(center_lat))
            
            y_pixel_size = (lat_range * lat_m_per_deg) / (grid_size - 1) if grid_size > 1 else 1
            x_pixel_size = (lng_range * lng_m_per_deg) / (grid_size - 1) if grid_size > 1 else 1
            
            # Calculate gradients
            gy, gx = np.gradient(dem)
            
            # Calculate slope magnitude in degrees
            slope_rad = np.arctan(np.sqrt((gx / x_pixel_size)**2 + (gy / y_pixel_size)**2))
            slope_deg = np.degrees(slope_rad)
            
            return {
                "mean_degrees": round(float(np.mean(slope_deg)), 1),
                "max_degrees": round(float(np.max(slope_deg)), 1),
                "min_degrees": round(float(np.min(slope_deg)), 1),
                "steep_area_percent": round(float(np.sum(slope_deg > 15) / slope_deg.size * 100), 1)
            }
            
        except Exception as e:
            print(f"⚠️ Slope calculation error: {e}")
            return self._estimate_slope_from_range(elevations, bbox)

    def _estimate_slope_from_range(self, elevations: list, bbox: dict) -> dict:
        """
        Fallback slope estimation from elevation range
        """
        elev_range = max(elevations) - min(elevations)
        
        # Estimate horizontal distance
        lat_range = abs(float(bbox['max_lat']) - float(bbox['min_lat']))
        lng_range = abs(float(bbox['max_lng']) - float(bbox['min_lng']))
        
        center_lat = (float(bbox['max_lat']) + float(bbox['min_lat'])) / 2
        horiz_dist = math.sqrt(
            (lat_range * 111320)**2 + 
            (lng_range * 111320 * math.cos(math.radians(center_lat)))**2
        )
        
        if horiz_dist > 0:
            avg_slope = math.degrees(math.atan(elev_range / horiz_dist))
        else:
            avg_slope = 0
        
        return {
            "mean_degrees": round(avg_slope, 1),
            "max_degrees": round(avg_slope * 1.5, 1),  # Estimate
            "min_degrees": 0,
            "steep_area_percent": 0,
            "note": "Estimated from elevation range (grid calculation failed)"
        }

    def _calculate_aspect(self, elevations: list) -> dict:
        """
        Calculate aspect (slope direction) from elevation grid
        """
        try:
            grid_size = int(math.sqrt(len(elevations)))
            if grid_size * grid_size != len(elevations) or grid_size < 2:
                return {
                    "dominant_direction": "unknown",
                    "note": "Insufficient data for aspect calculation"
                }
            
            dem = np.array(elevations).reshape(grid_size, grid_size)
            gy, gx = np.gradient(dem)
            
            # Calculate aspect in degrees (0° = North, 90° = East)
            aspect_rad = np.arctan2(-gx, gy)
            aspect_deg = np.degrees(aspect_rad)
            aspect_deg = np.where(aspect_deg < 0, 360 + aspect_deg, aspect_deg)
            
            # Calculate percentages for each direction
            north_facing = np.sum((aspect_deg > 315) | (aspect_deg < 45)) / aspect_deg.size * 100
            south_facing = np.sum((aspect_deg > 135) & (aspect_deg < 225)) / aspect_deg.size * 100
            east_facing = np.sum((aspect_deg >= 45) & (aspect_deg < 135)) / aspect_deg.size * 100
            west_facing = np.sum((aspect_deg >= 225) & (aspect_deg <= 315)) / aspect_deg.size * 100
            
            # Determine dominant direction
            directions = {
                'N': north_facing,
                'S': south_facing,
                'E': east_facing,
                'W': west_facing
            }
            dominant = max(directions, key=directions.get)
            
            return {
                "dominant_direction": dominant,
                "north_facing_percent": round(north_facing, 1),
                "south_facing_percent": round(south_facing, 1),
                "east_facing_percent": round(east_facing, 1),
                "west_facing_percent": round(west_facing, 1),
                "note": "North-facing slopes retain more moisture (beneficial in dry climates)"
            }
            
        except Exception as e:
            print(f"⚠️ Aspect calculation error: {e}")
            return {
                "dominant_direction": "unknown",
                "note": f"Aspect calculation failed: {e}"
            }

    def _assess_slope_suitability(self, mean_slope: float) -> dict:
        """
        Assess slope suitability for forestry operations
        """
        if mean_slope < 5:
            return {
                "rating": "excellent",
                "difficulty": "easy",
                "description": "Flat to gentle slopes. Ideal for planting.",
                "mechanization": "Full mechanization possible (machinery can access all areas)",
                "erosion_risk": "very low",
                "cost_multiplier": 1.0
            }
        elif mean_slope < 15:
            return {
                "rating": "good",
                "difficulty": "moderate",
                "description": "Moderate slopes. Suitable for most restoration projects.",
                "mechanization": "Limited mechanization. Manual planting feasible throughout.",
                "erosion_risk": "low",
                "cost_multiplier": 1.2
            }
        elif mean_slope < 25:
            return {
                "rating": "challenging",
                "difficulty": "difficult",
                "description": "Steep slopes. Erosion control critical.",
                "mechanization": "Manual planting only. Contour planting required.",
                "erosion_risk": "medium-high",
                "cost_multiplier": 1.5
            }
        else:
            return {
                "rating": "very difficult",
                "difficulty": "very difficult",
                "description": "Very steep terrain. Specialized techniques required.",
                "mechanization": "Hand planting only. Terracing may be needed.",
                "erosion_risk": "high",
                "cost_multiplier": 2.0
            }

    def _classify_ruggedness(self, elevation_range: float, mean_slope: float) -> dict:
        """
        Classify overall terrain ruggedness
        """
        if elevation_range < 50 and mean_slope < 5:
            return {
                "classification": "flat",
                "note": "Very flat terrain. Easy access and planting conditions."
            }
        elif elevation_range < 100 and mean_slope < 10:
            return {
                "classification": "gentle",
                "note": "Gentle rolling terrain. Good for most restoration activities."
            }
        elif elevation_range < 200 and mean_slope < 20:
            return {
                "classification": "undulating",
                "note": "Moderate terrain variation. Manageable for restoration."
            }
        elif elevation_range < 500:
            return {
                "classification": "hilly",
                "note": "Significant elevation changes. Careful planning required."
            }
        else:
            return {
                "classification": "mountainous",
                "note": "Mountainous terrain. Specialized restoration techniques needed."
            }

    def _generate_planting_recommendations(self, slope_stats: dict, suitability: dict) -> dict:
        """
        Generate planting recommendations based on terrain
        """
        techniques = []
        equipment = []
        
        mean_slope = slope_stats.get('mean_degrees', 0)
        steep_percent = slope_stats.get('steep_area_percent', 0)
        
        # Techniques based on slope
        if mean_slope < 5:
            techniques.append("Standard grid planting pattern suitable")
            equipment.append("Mechanical planter or manual dibble bars")
        elif mean_slope < 15:
            techniques.append("Contour planting recommended to follow elevation lines")
            techniques.append("Manual planting on steeper sections")
            equipment.append("Manual planting tools (dibble bars, mattocks)")
            equipment.append("Light machinery for gentle slopes (<10°)")
        else:
            techniques.append("Contour planting required across all areas")
            techniques.append("Consider terracing for very steep sections")
            techniques.append("Use erosion control measures (silt fencing, mulching)")
            equipment.append("Hand planting tools only")
            equipment.append("Erosion control materials (silt fence, biodegradable blankets)")
        
        # Erosion control
        if suitability.get('erosion_risk') in ['medium-high', 'high']:
            techniques.append("Install erosion control before planting")
            techniques.append("Use ground cover crops between tree rows")
            equipment.append("Erosion control mats/blankets")
        
        # Steep area handling
        if steep_percent > 20:
            techniques.append(f"~{steep_percent:.0f}% of area is steep (>15°) - prioritize these for erosion control")
        
        return {
            "difficulty_level": suitability['difficulty'],
            "access_rating": suitability['rating'],
            "techniques_required": techniques,
            "equipment_needed": equipment
        }

    def _unavailable_response(self, error: str) -> dict:
        """
        Return standardized response when terrain data unavailable
        """
        return {
            "available": False,
            "error": error,
            "note": "Detailed terrain analysis unavailable. Elevation data could not be fetched.",
            "recommendation": "Conduct ground survey for slope assessment before planting",
            "estimated_difficulty": "unknown",
            "confidence": "none",
            "data_source": "N/A"
        }
