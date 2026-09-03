"""
Sentinel-2 Satellite Verification Agent

Uses Google Earth Engine to verify deforestation events with 10m resolution
Sentinel-2 imagery. Provides before/after comparison, vegetation indices,
and change detection analysis.

Data Source: Sentinel-2 MSI Level-2A Surface Reflectance (COPERNICUS/S2_SR)
Attribution: Contains modified Copernicus Sentinel data
"""

import ee
from datetime import datetime, timedelta
import traceback


class SentinelVerificationAgent:
    def __init__(self):
        """Initialize Earth Engine with service account or user credentials"""
        try:
            # Try to initialize Earth Engine
            ee.Initialize()
            self.available = True
            print("✅ Earth Engine initialized successfully")
        except Exception as e:
            print(f"⚠️ Earth Engine initialization failed: {e}")
            print("   Sentinel verification will be unavailable")
            self.available = False
    
    def verify_with_sentinel(self, lat, lng, alert_date=None, area_ha=0):
        """
        Verify deforestation with Sentinel-2 imagery
        
        Args:
            lat: Latitude of deforestation center
            lng: Longitude of deforestation center
            alert_date: Date of alert (defaults to current date)
            area_ha: Area in hectares (for context)
        
        Returns:
            dict: Comprehensive verification report with imagery URLs and analysis
        """
        if not self.available:
            return {
                "available": False,
                "error": "Earth Engine not initialized",
                "message": "Sentinel verification requires Earth Engine authentication"
            }
        
        try:
            # Default to current date if not provided
            if alert_date is None:
                alert_date = datetime.utcnow()
            elif isinstance(alert_date, str):
                alert_date = datetime.fromisoformat(alert_date.replace('Z', '+00:00'))
            
            # Define Area of Interest (AOI)
            # Use ~1km buffer around point for analysis
            buffer_meters = 1000
            point = ee.Geometry.Point([lng, lat])
            aoi = point.buffer(buffer_meters)
            
            # Calculate time windows
            before_end = alert_date - timedelta(days=30)
            before_start = before_end - timedelta(days=90)  # 90-day window
            
            after_start = alert_date + timedelta(days=30)
            after_end = datetime.utcnow()
            
            # Ensure we have enough time for after period
            if (after_end - after_start).days < 30:
                after_start = after_end - timedelta(days=90)
            
            # Get Sentinel-2 collections
            s2 = ee.ImageCollection('COPERNICUS/S2_SR')
            
            # Before period composite
            before_collection = s2.filterBounds(aoi).filterDate(
                before_start.strftime('%Y-%m-%d'),
                before_end.strftime('%Y-%m-%d')
            )
            
            # After period composite
            after_collection = s2.filterBounds(aoi).filterDate(
                after_start.strftime('%Y-%m-%d'),
                after_end.strftime('%Y-%m-%d')
            )
            
            # Apply cloud masking and create composites
            before_composite = self._create_cloud_free_composite(before_collection, aoi)
            after_composite = self._create_cloud_free_composite(after_collection, aoi)
            
            # Calculate vegetation indices
            before_indices = self._calculate_vegetation_indices(before_composite)
            after_indices = self._calculate_vegetation_indices(after_composite)
            
            # Change detection
            change_analysis = self._detect_changes(before_indices, after_indices, aoi)
            
            # Generate image URLs
            imagery_urls = self._generate_image_urls(
                before_composite, after_composite,
                before_indices, after_indices,
                change_analysis, aoi
            )
            
            # Get metadata
            before_count = before_collection.size().getInfo()
            after_count = after_collection.size().getInfo()
            
            before_cloud = self._get_cloud_cover(before_collection)
            after_cloud = self._get_cloud_cover(after_collection)
            
            return {
                "available": True,
                "imagery": {
                    **imagery_urls,
                    "before_date_range": f"{before_start.strftime('%Y-%m-%d')} to {before_end.strftime('%Y-%m-%d')}",
                    "after_date_range": f"{after_start.strftime('%Y-%m-%d')} to {after_end.strftime('%Y-%m-%d')}",
                    "resolution_m": 10,
                    "scenes_used_before": before_count,
                    "scenes_used_after": after_count,
                    "cloud_cover_before_percent": round(before_cloud, 1),
                    "cloud_cover_after_percent": round(after_cloud, 1)
                },
                "vegetation_indices": change_analysis.get('indices', {}),
                "forest_loss_verified": change_analysis.get('verification', {}),
                "metadata": {
                    "data_source": "Sentinel-2 MSI Level-2A (ESA Copernicus)",
                    "processing_method": "Cloud-masked median composite",
                    "attribution": "Contains modified Copernicus Sentinel data 2023-2025",
                    "buffer_radius_m": buffer_meters
                }
            }
        
        except Exception as e:
            print(f"❌ Sentinel verification failed: {e}")
            traceback.print_exc()
            return {
                "available": False,
                "error": str(e),
                "message": "Sentinel verification encountered an error"
            }
    
    def _create_cloud_free_composite(self, collection, aoi):
        """Create cloud-free composite using SCL band masking"""
        
        def mask_clouds(image):
            """Mask clouds using Scene Classification Layer (SCL)"""
            scl = image.select('SCL')
            
            # Mask out: clouds (9), cloud shadows (3), cirrus (10)
            # Keep: vegetation (4), bare soil (5), water (6), unclassified (7)
            mask = scl.neq(9).And(scl.neq(3)).And(scl.neq(10))
            
            return image.updateMask(mask)
        
        # Apply cloud mask and create median composite
        cloud_free = collection.map(mask_clouds)
        composite = cloud_free.median().clip(aoi)
        
        return composite
    
    def _calculate_vegetation_indices(self, image):
        """Calculate NDVI, EVI, and NDMI"""
        
        # NDVI = (NIR - Red) / (NIR + Red)
        ndvi = image.normalizedDifference(['B8', 'B4']).rename('NDVI')
        
        # EVI = 2.5 * ((NIR - Red) / (NIR + 6*Red - 7.5*Blue + 1))
        nir = image.select('B8')
        red = image.select('B4')
        blue = image.select('B2')
        
        evi = nir.subtract(red).divide(
            nir.add(red.multiply(6)).subtract(blue.multiply(7.5)).add(1)
        ).multiply(2.5).rename('EVI')
        
        # NDMI = (NIR - SWIR1) / (NIR + SWIR1) - water/moisture stress
        ndmi = image.normalizedDifference(['B8', 'B11']).rename('NDMI')
        
        return image.addBands([ndvi, evi, ndmi])
    
    def _detect_changes(self, before_image, after_image, aoi):
        """Detect forest loss through NDVI change analysis"""
        
        before_ndvi = before_image.select('NDVI')
        after_ndvi = after_image.select('NDVI')
        before_evi = before_image.select('EVI')
        after_evi = after_image.select('EVI')
        before_ndmi = before_image.select('NDMI')
        after_ndmi = after_image.select('NDMI')
        
        # Calculate changes
        ndvi_change = after_ndvi.subtract(before_ndvi)
        evi_change = after_evi.subtract(before_evi)
        ndmi_change = after_ndmi.subtract(before_ndmi)
        
        # Threshold for significant forest loss: NDVI drop > 0.2
        loss_mask = ndvi_change.lt(-0.2)
        
        # Calculate statistics
        before_ndvi_mean = before_ndvi.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('NDVI')
        
        after_ndvi_mean = after_ndvi.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('NDVI')
        
        before_evi_mean = before_evi.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('EVI')
        
        after_evi_mean = after_evi.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('EVI')
        
        before_ndmi_mean = before_ndmi.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('NDMI')
        
        after_ndmi_mean = after_ndmi.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('NDMI')
        
        ndvi_change_mean = ndvi_change.reduceRegion(
            reducer=ee.Reducer.mean(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('NDVI')
        
        # Calculate area of loss (pixels * 100m² = hectares / 10000)
        pixel_count = loss_mask.reduceRegion(
            reducer=ee.Reducer.sum(),
            geometry=aoi,
            scale=10,
            maxPixels=1e9
        ).get('NDVI')
        
        # Get actual values
        before_ndvi_val = before_ndvi_mean.getInfo() if before_ndvi_mean else 0
        after_ndvi_val = after_ndvi_mean.getInfo() if after_ndvi_mean else 0
        ndvi_change_val = ndvi_change_mean.getInfo() if ndvi_change_mean else 0
        
        before_evi_val = before_evi_mean.getInfo() if before_evi_mean else 0
        after_evi_val = after_evi_mean.getInfo() if after_evi_mean else 0
        
        before_ndmi_val = before_ndmi_mean.getInfo() if before_ndmi_mean else 0
        after_ndmi_val = after_ndmi_mean.getInfo() if after_ndmi_mean else 0
        
        pixel_count_val = pixel_count.getInfo() if pixel_count else 0
        area_ha = (pixel_count_val * 100) / 10000  # 10m pixels = 100m² each
        
        # Interpret NDVI change
        if ndvi_change_val < -0.3:
            interpretation = "Severe vegetation loss detected"
        elif ndvi_change_val < -0.2:
            interpretation = "Significant vegetation loss detected"
        elif ndvi_change_val < -0.1:
            interpretation = "Moderate vegetation change detected"
        else:
            interpretation = "No significant vegetation loss detected"
        
        # Water stress level from NDMI
        ndmi_change_val = after_ndmi_val - before_ndmi_val
        if ndmi_change_val < -0.2:
            water_stress = "high"
        elif ndmi_change_val < -0.1:
            water_stress = "moderate"
        else:
            water_stress = "low"
        
        # Confidence level
        if abs(ndvi_change_val) > 0.3 and pixel_count_val > 100:
            confidence = "very_high"
        elif abs(ndvi_change_val) > 0.2 and pixel_count_val > 50:
            confidence = "high"
        elif abs(ndvi_change_val) > 0.1:
            confidence = "medium"
        else:
            confidence = "low"
        
        return {
            "indices": {
                "ndvi": {
                    "before_mean": round(before_ndvi_val, 3) if before_ndvi_val else None,
                    "after_mean": round(after_ndvi_val, 3) if after_ndvi_val else None,
                    "change_mean": round(ndvi_change_val, 3) if ndvi_change_val else None,
                    "interpretation": interpretation
                },
                "evi": {
                    "before_mean": round(before_evi_val, 3) if before_evi_val else None,
                    "after_mean": round(after_evi_val, 3) if after_evi_val else None,
                    "change_mean": round(after_evi_val - before_evi_val, 3) if (before_evi_val and after_evi_val) else None
                },
                "ndmi": {
                    "before_mean": round(before_ndmi_val, 3) if before_ndmi_val else None,
                    "after_mean": round(after_ndmi_val, 3) if after_ndmi_val else None,
                    "change_mean": round(ndmi_change_val, 3) if ndmi_change_val else None,
                    "water_stress_level": water_stress
                }
            },
            "verification": {
                "area_ha": round(area_ha, 2),
                "pixel_count": int(pixel_count_val) if pixel_count_val else 0,
                "confidence": confidence
            },
            "change_image": ndvi_change
        }
    
    def _generate_image_urls(self, before_composite, after_composite, 
                            before_indices, after_indices, change_analysis, aoi):
        """Generate thumbnail URLs for visualization"""
        
        # RGB visualization parameters
        rgb_vis = {
            'bands': ['B4', 'B3', 'B2'],
            'min': 0,
            'max': 3000,
            'gamma': 1.4
        }
        
        # NDVI visualization parameters
        ndvi_vis = {
            'min': -0.2,
            'max': 0.8,
            'palette': ['red', 'yellow', 'green']
        }
        
        # Generate URLs (valid for 3 days)
        try:
            before_rgb_url = before_composite.getThumbURL({
                **rgb_vis,
                'region': aoi,
                'dimensions': 1024,
                'format': 'png'
            })
            
            after_rgb_url = after_composite.getThumbURL({
                **rgb_vis,
                'region': aoi,
                'dimensions': 1024,
                'format': 'png'
            })
            
            before_ndvi_url = before_indices.select('NDVI').getThumbURL({
                **ndvi_vis,
                'region': aoi,
                'dimensions': 1024,
                'format': 'png'
            })
            
            after_ndvi_url = after_indices.select('NDVI').getThumbURL({
                **ndvi_vis,
                'region': aoi,
                'dimensions': 1024,
                'format': 'png'
            })
            
            ndvi_change_url = change_analysis['change_image'].getThumbURL({
                'min': -0.5,
                'max': 0.2,
                'palette': ['darkred', 'red', 'orange', 'yellow', 'white', 'lightgreen'],
                'region': aoi,
                'dimensions': 1024,
                'format': 'png'
            })
            
            return {
                "before_rgb_url": before_rgb_url,
                "after_rgb_url": after_rgb_url,
                "before_ndvi_url": before_ndvi_url,
                "after_ndvi_url": after_ndvi_url,
                "ndvi_change_url": ndvi_change_url
            }
        except Exception as e:
            print(f"⚠️ Error generating image URLs: {e}")
            return {
                "before_rgb_url": None,
                "after_rgb_url": None,
                "before_ndvi_url": None,
                "after_ndvi_url": None,
                "ndvi_change_url": None,
                "error": "Failed to generate visualization URLs"
            }
    
    def _get_cloud_cover(self, collection):
        """Calculate average cloud cover for collection"""
        try:
            cloud_cover = collection.aggregate_mean('CLOUDY_PIXEL_PERCENTAGE')
            return cloud_cover.getInfo() if cloud_cover else 0
        except:
            return 0
