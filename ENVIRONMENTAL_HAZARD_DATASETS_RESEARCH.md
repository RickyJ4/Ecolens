# Environmental Hazard Datasets: Comprehensive API & Data Source Reference

> Research compiled: March 2026
> All sources verified via web research; all datasets listed are FREE and publicly accessible.

---

## 1. WILDFIRES

### 1.1 NASA FIRMS (Fire Information for Resource Management System)

| Attribute | Details |
|-----------|---------|
| **API Base URL** | `https://firms.modaps.eosdis.nasa.gov/api/area/{FORMAT}/{MAP_KEY}/{SOURCE}/{AREA_COORDINATES}/{DAY_RANGE}/{DATE}` |
| **Data Availability Endpoint** | `https://firms.modaps.eosdis.nasa.gov/api/data_availability/` |
| **Map Key Registration** | `https://firms.modaps.eosdis.nasa.gov/api/map_key/` |
| **KML Fire Footprints** | `https://firms.modaps.eosdis.nasa.gov/api/kml_fire_footprints/` |
| **Data Formats** | CSV, KML, SHP, GeoJSON (via WFS) |
| **Spatial Resolution** | MODIS: 1 km; VIIRS (SNPP/NOAA-20/NOAA-21): 375 m; Landsat: 30 m (US/Canada only) |
| **Temporal Resolution** | Ultra Real-Time (URT): <60 sec (US/Canada); Near Real-Time (NRT): ~60 min; Standard: ~2 months latency |
| **Update Frequency** | Multiple times daily (each satellite overpass) |
| **Authentication** | Free MAP_KEY required (register with email) |
| **Rate Limits** | 5,000 transactions per 10-minute interval |
| **Python Libraries** | `requests`, `pandas`, `geopandas` |

**Sensor/Source Codes for API:**
- `MODIS_NRT` / `MODIS_SP` (standard processing)
- `VIIRS_SNPP_NRT` / `VIIRS_SNPP_SP`
- `VIIRS_NOAA20_NRT` / `VIIRS_NOAA20_SP`
- `VIIRS_NOAA21_NRT`
- `LANDSAT_NRT` (US/Canada only)

**Area Parameter:** Bounding box as `west,south,east,north` or `world` for global.

**Day Range:** 1-5 days.

**Example API Call:**
```
https://firms.modaps.eosdis.nasa.gov/api/area/csv/{MAP_KEY}/VIIRS_NOAA20_NRT/-125,24,-66,50/1/2026-03-22
```

---

### 1.2 NIFC (National Interagency Fire Center) - Wildfire Perimeters

| Attribute | Details |
|-----------|---------|
| **Current Fire Perimeters (ArcGIS FeatureServer)** | `https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/Current_WildlandFire_Perimeters/FeatureServer/0` |
| **Public Wildfire Perimeters View** | `https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/Public_Wildfire_Perimeters_View/FeatureServer` |
| **Historical Perimeters (WFIGS)** | `https://data-nifc.opendata.arcgis.com/datasets/nifc::wfigs-interagency-fire-perimeters/` |
| **Open Data Hub** | `https://data-nifc.opendata.arcgis.com/` |
| **Data Formats** | GeoJSON, Shapefile, CSV, KML, File Geodatabase (via ArcGIS REST API query) |
| **Spatial Resolution** | Vector polygon perimeters (variable accuracy) |
| **Temporal Resolution** | Refreshed every 5 minutes (up to 15 min display lag) |
| **Authentication** | None required |
| **Rate Limits** | Standard ArcGIS Online rate limits |
| **Python Libraries** | `requests`, `geopandas`, `arcgis` (ArcGIS Python API) |

**Query Example (GeoJSON):**
```
https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/Current_WildlandFire_Perimeters/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson
```

---

### 1.3 MODIS and VIIRS Active Fire Products

These are the underlying satellite products behind FIRMS:

| Product | Sensor | Resolution | Revisit | Platform |
|---------|--------|------------|---------|----------|
| MOD14/MYD14 | MODIS | 1 km | ~daily (Terra+Aqua combined) | Terra/Aqua |
| VNP14IMG | VIIRS | 375 m | ~12 hours | Suomi NPP |
| VJ114IMG | VIIRS | 375 m | ~12 hours | NOAA-20 |
| VJ214IMG | VIIRS | 375 m | ~12 hours | NOAA-21 |

**Direct access via NASA Earthdata:** `https://www.earthdata.nasa.gov/`
**FIRMS is the recommended access path** (wraps these products with a simpler API).

---

## 2. FLOODS

### 2.1 NOAA National Water Prediction Service (NWPS)

| Attribute | Details |
|-----------|---------|
| **Base URL** | `https://api.water.noaa.gov/nwps/v1/` |
| **API Docs (Swagger)** | `https://api.water.noaa.gov/nwps/v1/docs/` |
| **HEFS API (Ensemble Forecasts)** | `https://api.water.noaa.gov/hefs/v1/` |
| **HEFS API Docs** | `https://api.water.noaa.gov/hefs/v1/docs/` |
| **Data Format** | JSON |
| **Spatial Coverage** | US river gauges (thousands of locations) |
| **Temporal Resolution** | Real-time observations + forecasts |
| **Authentication** | None required |
| **Rate Limits** | Not published; service is "experimental" and not 24/7 supported |
| **Python Libraries** | `requests`, `hydrotools` (NOAA OWP) |

**Key Endpoints:**
```
GET /v1/gauges                              # List all gauges
GET /v1/gauges/{identifier}                 # Gauge metadata
GET /v1/gauges/{identifier}/stageflow       # Observed + forecast stage/flow
GET /v1/gauges/{identifier}/stageflow/{product}  # Specific product
GET /v1/gauges/{identifier}/ratings         # Rating curves
```

**Example:**
```
https://api.water.noaa.gov/nwps/v1/gauges/LOLT2/stageflow
```

**Data includes:** NWS streamflow forecasts, stream observations, National Water Model output, crest history, flood impacts, low water history, flood category levels.

---

### 2.2 Global Flood Monitoring System (GFMS)

| Attribute | Details |
|-----------|---------|
| **Website** | `http://flood.umd.edu/` |
| **Data Access** | Direct download from web interface; FTP available on request |
| **Data Formats** | Binary grids, GeoTIFF, PNG maps |
| **Spatial Resolution** | 1/8 degree (~12 km) for runoff/storage; 1 km for inundation |
| **Temporal Resolution** | Updated every 3 hours |
| **Coverage** | Quasi-global (50N - 50S) |
| **Authentication** | None for web downloads |
| **Rate Limits** | Not published |
| **Python Libraries** | `requests`, `rasterio`, `xarray` |

**Products:** Streamflow, surface water storage, inundation maps, precipitation totals (1-day, 3-day, 7-day).

**Data Source:** Uses GPM IMERG precipitation as input to a hydrological runoff/routing model.

---

### 2.3 GloFAS (Global Flood Awareness System) via CEMS Early Warning Data Store

| Attribute | Details |
|-----------|---------|
| **API Endpoint** | `https://ewds.climate.copernicus.eu/api` |
| **Portal** | `https://global-flood.emergency.copernicus.eu/` |
| **Data Formats** | GRIB, NetCDF |
| **Spatial Resolution** | 0.05 degrees (~5 km) for GloFAS v4; 0.1 degrees (~11 km) for v3 |
| **Temporal Resolution** | Daily forecasts (up to 30 days ahead); historical reanalysis from 1979 |
| **Authentication** | Free Copernicus ECMWF account required; personal access token |
| **Rate Limits** | Queued processing; not published |
| **Python Libraries** | `cdsapi` (v0.7.7+), `xarray`, `cfgrib` |

**Setup (`.cdsapirc` file):**
```
url: https://ewds.climate.copernicus.eu/api
key: <PERSONAL-ACCESS-TOKEN>
```

**Python Example:**
```python
import cdsapi
client = cdsapi.Client()
dataset = 'cems-glofas-historical'
request = {
    'hydrological_model': ['htessel_lisflood'],
    'product_type': ['consolidated'],
    'variable': ['mean_discharge_in_the_last_24_hours'],
    'hyear': ['2020'],
    'hmonth': ['12'],
    'hday': ['25'],
    'data_format': 'grib',
    'system_version': ['version_2_1'],
}
client.retrieve(dataset, request, 'download.grib')
```

**Available Datasets:** `cems-glofas-historical`, `cems-glofas-forecast`, `cems-glofas-reforecast`, `cems-glofas-seasonal`.

---

### 2.4 Open-Meteo Global Flood API (GloFAS wrapper - no auth required)

| Attribute | Details |
|-----------|---------|
| **API Endpoint** | `https://flood-api.open-meteo.com/v1/flood` |
| **Data Format** | JSON (default), CSV, XLSX |
| **Spatial Resolution** | 0.05 degrees (~5 km) |
| **Temporal Resolution** | Daily; historical from 1984; forecast up to 7 months |
| **Authentication** | None (free for non-commercial use) |
| **Rate Limits** | Not strictly published; commercial tier available |
| **Python Libraries** | `requests`, `openmeteo-requests` |

**Parameters:** `latitude`, `longitude`, `daily` (variables), `start_date`, `end_date`, `forecast_days` (0-210), `ensemble` (boolean).

**Variables:** `river_discharge`, `river_discharge_mean`, `river_discharge_median`, `river_discharge_max`, `river_discharge_min`, `river_discharge_p25`, `river_discharge_p75`.

**Example:**
```
https://flood-api.open-meteo.com/v1/flood?latitude=59.91&longitude=10.75&daily=river_discharge
```

---

### 2.5 Copernicus Emergency Management Service - Global Flood Monitoring (GFM)

| Attribute | Details |
|-----------|---------|
| **Map Viewer** | `https://global-flood.emergency.copernicus.eu/` |
| **Data Source** | Sentinel-1 SAR imagery |
| **Spatial Resolution** | 20 m (Sentinel-1 pixel resolution) |
| **Temporal Resolution** | Near real-time (processed upon Sentinel-1 acquisition, ~6-12 day revisit) |
| **Authentication** | Free registration required for GloFAS Map Viewer |
| **Data Formats** | GeoTIFF, vector layers via WMS/WFS |

---

## 3. DROUGHT

### 3.1 US Drought Monitor

| Attribute | Details |
|-----------|---------|
| **API Base URL** | `https://usdmdataservices.unl.edu/api/` |
| **GIS Data** | `https://droughtmonitor.unl.edu/DmData/GISData.aspx` |
| **Data Formats** | JSON, XML, CSV (set via HTTP `Accept` header) |
| **Spatial Resolution** | County-level to national (vector boundaries) |
| **Temporal Resolution** | Weekly (updated every Thursday) |
| **Authentication** | None required |
| **Rate Limits** | Not published |
| **Python Libraries** | `requests`, `pandas`, `geopandas` |

**Area Types (16 geographic levels):**
`USStatistics`, `StateStatistics`, `CountyStatistics`, `HUCStatistics`, `FEMARegionStatistics`, `TribalStatistics`, `ClimateDivisionStatistics`, `ClimateHubStatistics`, `RegionalDroughtEarlyWarningSystemStatistics`, `WeatherForecastOfficeStatistics`, `USACEDistrictStatistics`, `USACEDivisionStatistics`, `UrbanAreaStatistics`, `RiverForecastCenterStatistics`, `RegionalClimateCenterStatistics`, `NWSRegionStatistics`

**Statistics Endpoints:**
```
/api/{AreaType}/GetDroughtSeverityStatisticsByArea?aoi={aoi}&startdate={M/D/YYYY}&enddate={M/D/YYYY}&statisticsType={1|2}
/api/{AreaType}/GetDroughtSeverityStatisticsByAreaPercent
/api/{AreaType}/GetDroughtSeverityStatisticsByPopulation
/api/{AreaType}/GetDroughtSeverityStatisticsByPopulationPercent
/api/{AreaType}/GetDSCI
/api/{AreaType}/GetBasicStatisticsByAreaPercent?aoi={aoi}&dx={0-4}&DxLevelThresholdFrom={0-100}&DxLevelThresholdTo={0-100}&...
/api/ConsecutiveNonConsecutiveStatistics/GetConsecutiveWeeksCounty?aoi={state}&dx={0-4}&minimumweeks={N}&...
/api/ConsecutiveNonConsecutiveStatistics/GetNonConsecutiveStatisticsCounty
```

**AOI Codes:** `us`, `conus`, `total` (national); 2-digit FIPS (state); 5-digit FIPS (county); HUC IDs (2/4/6/8 digit).

**Drought Levels:** D0=0, D1=1, D2=2, D3=3, D4=4.

**Example:**
```
https://usdmdataservices.unl.edu/api/USStatistics/GetDroughtSeverityStatisticsByArea?aoi=us&startdate=1/1/2024&enddate=1/1/2025&statisticsType=1
```

---

### 3.2 SPEI Global Drought Monitor

| Attribute | Details |
|-----------|---------|
| **Website** | `https://spei.csic.es/` |
| **Global Drought Monitor Map** | `https://spei.csic.es/map/` |
| **SPEIbase v2.11 Download** | `https://spei.csic.es/spei_database_2_11` |
| **Previous Versions** | `https://digital.csic.es/handle/10261/336288` |
| **Data Format** | NetCDF (classic model) |
| **Spatial Resolution** | 0.5 degrees (~55 km) |
| **Temporal Resolution** | Monthly |
| **Time Coverage** | January 1901 - December 2024 (v2.11) |
| **SPEI Timescales** | 1 to 48 months |
| **Authentication** | Login required for full database download |
| **Rate Limits** | N/A (bulk download) |
| **Python Libraries** | `xarray`, `netCDF4`, `scipy` |
| **Also on** | Google Earth Engine (v2.10) |

**Data Source:** CRU TS 4.09 precipitation/temperature; FAO-56 Penman-Monteith PET estimation.

---

### 3.3 NASA GRACE/GRACE-FO Satellite Groundwater Data

| Attribute | Details |
|-----------|---------|
| **Data Portal** | `https://grace.jpl.nasa.gov/data/get-data/` |
| **Interactive Data Browser** | `https://grace.jpl.nasa.gov/data/data-analysis-tool/` |
| **Groundwater Drought Indicators** | `https://nasagrace.unl.edu/` |
| **NASA Earthdata (GES DISC)** | `https://www.earthdata.nasa.gov/` |
| **Data Format** | NetCDF |
| **Spatial Resolution** | 0.25 x 0.25 degrees (groundwater indicators); 0.5 degrees (JPL mascons); 1 degree (mass grids) |
| **Temporal Resolution** | Monthly (mass grids); weekly drought indicators (Monday) |
| **Time Coverage** | February 2003 - present (3-6 month latency) |
| **Authentication** | NASA Earthdata Login required (`https://urs.earthdata.nasa.gov/`) |
| **Rate Limits** | Not published |
| **Python Libraries** | `earthaccess`, `xarray`, `netCDF4`, `requests` |

**Key Products:**
- JPL Global Mascons (0.5-degree, monthly)
- Monthly Land Water Mass Grids (1-degree)
- GRACE-DA-DM Groundwater/Soil Moisture Drought Indicators (0.25-degree, weekly)
- GLDAS Land Water Content (comparison dataset)

**Programmatic Access:** Use `earthaccess` Python library or set up `.netrc` file with Earthdata credentials, then download via shell scripts or Python `requests`.

---

## 4. GLACIAL RETREAT

### 4.1 GLIMS (Global Land Ice Measurements from Space)

| Attribute | Details |
|-----------|---------|
| **Interactive Map/Download** | `https://www.glims.org/glacierdata/` |
| **WMS Endpoint** | `https://www.glims.org/geoserver/ows?service=wms&version=1.3.0&request=GetCapabilities` |
| **WFS Endpoint** | `https://www.glims.org/geoserver/ows?service=wfs&version=2.0.0&request=GetCapabilities` |
| **NSIDC Archive** | `https://nsidc.org/data/nsidc-0272/versions/1` |
| **Data Formats** | Shapefile, KML, GML, MapInfo, WMS/WFS |
| **Spatial Resolution** | Variable (derived from Landsat 30m, Sentinel-2 10m) |
| **Temporal Coverage** | 1950s - present (most data post-2000) |
| **Authentication** | None for WMS/WFS; NSIDC login for bulk downloads |
| **Python Libraries** | `owslib` (WMS/WFS), `geopandas`, `requests` |

---

### 4.2 RGI (Randolph Glacier Inventory) 7.0

| Attribute | Details |
|-----------|---------|
| **Main Page** | `https://www.glims.org/RGI/` |
| **User Guide** | `https://glims-rgi.github.io/rgi_user_guide/` |
| **NSIDC Download** | `https://nsidc.org/data/nsidc-0770/versions/4` |
| **Data Formats** | Shapefile (vector outlines with topographic attributes) |
| **Coverage** | Global (>215,000 glaciers) |
| **Version** | 7.0 (released 2023) |
| **Attributes** | Area, min/max/median elevation, slope, aspect |
| **Authentication** | NSIDC Earthdata login for download |
| **Python Libraries** | `geopandas`, `earthaccess` |

---

### 4.3 NASA ITS_LIVE (MEaSUREs Inter-mission Time Series of Land Ice Velocity and Elevation)

| Attribute | Details |
|-----------|---------|
| **STAC API** | `https://stac.itslive.cloud` |
| **Data Portal** | `https://nsidc.org/apps/itslive/` |
| **Interactive Dashboard** | `https://itslive-dashboard.labs.nsidc.org/` |
| **Datacube Catalog** | `https://its-live-data.s3.amazonaws.com/datacubes/catalog_v02.json` (GeoJSON, ~5 MB) |
| **Data Formats** | NetCDF, GeoTIFF, Zarr (cloud-optimized datacubes), QGIS VRT |
| **Spatial Resolution** | 120 m (velocity); 240-1920 m (elevation/extent) |
| **Temporal Coverage** | 1985 - present |
| **Frequency** | Variable (monthly, annual, quarterly composites) |
| **Authentication** | V1 data: NASA Earthdata Login; V2 data: open access |
| **Python Libraries** | `pystac-client`, `xarray`, `earthaccess`, `zarr` |

**Python Access:**
```python
from pystac_client import Client
import xarray as xr

catalog = Client.open("https://stac.itslive.cloud")
results = catalog.search(collections=["itslive-cubes"], intersects=point_geometry)
for item in results.items():
    ds = xr.open_zarr(item.assets['zarr'].href)
```

**STAC Collections:** `itslive-granules` (individual image pairs), `itslive-cubes` (Zarr datacubes).

---

### 4.4 ESA CCI Glacier Datasets

| Attribute | Details |
|-----------|---------|
| **Open Data Portal** | `https://climate.esa.int/en/odp/#/dashboard` |
| **Dedicated Download** | `http://glaciers-cci.enveo.at/crdp2/index.html` |
| **CCI Toolbox (Python)** | `https://climate.esa.int/en/data/toolbox/` |
| **Data Formats** | Shapefile (outlines), GeoTIFF (elevation changes, velocities), NetCDF |
| **Products** | Glacier outlines, elevation changes, flow velocities |
| **Source Data** | Landsat, Sentinel-2, Sentinel-1 SAR, CryoSat-2, TanDEM-X |
| **Authentication** | Free registration on CCI Open Data Portal |
| **Data Policy** | Freely available without restrictions |
| **Python Libraries** | `ccitools` (CCI Toolbox), `geopandas`, `rasterio` |

---

## 5. NDVI / VEGETATION STRESS

### 5.1 Sentinel-2 via Copernicus Data Space Ecosystem (Sentinel Hub)

| Attribute | Details |
|-----------|---------|
| **Sentinel Hub Base URL** | `https://sh.dataspace.copernicus.eu` |
| **Process API** | `https://sh.dataspace.copernicus.eu/api/v1/process` |
| **Catalog API (STAC)** | `https://stac.dataspace.copernicus.eu/v1/` |
| **Token Endpoint** | `https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token` |
| **Data Format** | GeoTIFF, PNG, JPEG (output); JP2 (raw tiles) |
| **Spatial Resolution** | 10 m (B04, B08 for NDVI) |
| **Temporal Resolution** | 5-day revisit (Sentinel-2A + 2B combined) |
| **Authentication** | OAuth2 client credentials (free CDSE account) |
| **Rate Limits** | Quota tiers apply; see CDSE Quotas documentation |
| **Python Libraries** | `sentinelhub-py`, `pystac-client`, `openeo`, `rasterio` |

**NDVI Evalscript Example:**
```javascript
function evaluatePixel(sample) {
    let ndvi = (sample.B08 - sample.B04) / (sample.B08 + sample.B04);
    return [ndvi];
}
function setup() {
    return { input: ["B04", "B08"], output: { bands: 1, sampleType: "FLOAT32" } };
}
```

**Python Configuration:**
```python
from sentinelhub import SHConfig
config = SHConfig()
config.sh_client_id = '<your_client_id>'
config.sh_client_secret = '<your_client_secret>'
config.sh_token_url = 'https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token'
config.sh_base_url = 'https://sh.dataspace.copernicus.eu'
```

**Note (March 2026):** Additional API URL paths are rolling out alongside existing endpoints.

---

### 5.2 MODIS NDVI Products (MOD13Q1) via AppEEARS

| Attribute | Details |
|-----------|---------|
| **AppEEARS API Base URL** | `https://appeears.earthdatacloud.nasa.gov/api` |
| **Product ID** | `MOD13Q1.061` (Terra NDVI 16-day) |
| **Data Formats** | GeoTIFF, NetCDF4 (area requests); CSV (point requests) |
| **Spatial Resolution** | 250 m |
| **Temporal Resolution** | 16-day composite |
| **Time Coverage** | February 2000 - present |
| **Authentication** | NASA Earthdata Login (Basic Auth -> Bearer token, 48h validity) |
| **Rate Limits** | HTTP 429 on excess; no specific limit published |
| **Python Libraries** | `requests`, `earthaccess`, `modisfast` |

**Key API Endpoints:**
```
POST /login                          # Get bearer token
GET  /product                        # List all products
GET  /product/MOD13Q1.061            # List NDVI layers
POST /task                           # Submit area/point extraction
GET  /task/{task_id}                 # Check task status
GET  /bundle/{task_id}               # List output files
GET  /bundle/{task_id}/{file_id}     # Download file
```

**Python Example:**
```python
import requests

# Login
token_response = requests.post(
    'https://appeears.earthdatacloud.nasa.gov/api/login',
    auth=('username', 'password')
).json()
token = token_response['token']

# Submit NDVI extraction task
task = {
    'task_type': 'area',
    'task_name': 'ndvi-extraction',
    'params': {
        'dates': [{'startDate': '01-01-2025', 'endDate': '12-31-2025'}],
        'layers': [{'product': 'MOD13Q1.061', 'layer': '_250m_16_days_NDVI'}],
        'geo': {  # GeoJSON polygon
            'type': 'FeatureCollection',
            'features': [...]
        },
        'output': {'format': {'type': 'geotiff'}, 'projection': 'geographic'}
    }
}
requests.post('https://appeears.earthdatacloud.nasa.gov/api/task',
              json=task, headers={'Authorization': f'Bearer {token}'})
```

---

### 5.3 Landsat via USGS M2M API

| Attribute | Details |
|-----------|---------|
| **API Base URL** | `https://m2m.cr.usgs.gov/api/v1/` |
| **API Documentation** | `https://m2m.cr.usgs.gov/api/docs/json/` |
| **Data Format** | GeoTIFF (individual bands or bundles as .tar) |
| **Spatial Resolution** | 30 m (multispectral); 15 m (panchromatic) |
| **Temporal Resolution** | 16-day revisit per satellite (8-day combined Landsat 8+9) |
| **Authentication** | EarthExplorer account + M2M access approval + Application Token |
| **Rate Limits** | Not published |
| **Python Libraries** | `usgs-m2m-api`, `landsatxplore`, `earthaccess` |

**Key Endpoints:**
```
POST /login-token       # Auth with application token
POST /dataset-search    # Find datasets
POST /scene-search      # Search scenes by spatial/temporal criteria
POST /download-options  # Get download options for scenes
POST /download-request  # Request downloads
POST /download-retrieve # Get download URLs
POST /logout            # End session
```

**M2M Access Request:** `https://ers.cr.usgs.gov/profile/access`

**Note:** The `login` endpoint was deprecated Feb 2025; use `login-token` with an encrypted 64-bit application token.

---

### 5.4 Google Earth Engine

| Attribute | Details |
|-----------|---------|
| **Python API (PyPI)** | `earthengine-api` (v1.7.18+) |
| **Registration** | `https://code.earthengine.google.com/register` |
| **REST API** | `https://earthengine.googleapis.com/` |
| **Data Format** | In-platform (export to GeoTIFF, CSV, TFRecord to Google Drive/Cloud Storage) |
| **Available NDVI Collections** | `MODIS/061/MOD13Q1`, `COPERNICUS/S2_SR_HARMONIZED`, `LANDSAT/LC09/C02/T1_L2` |
| **Authentication** | Google account + Earth Engine project registration |
| **Rate Limits** | Quota tiers (Community Tier default after April 27, 2026) |
| **Python Libraries** | `ee` (earthengine-api), `geemap` |

**Python Example:**
```python
import ee
ee.Authenticate()
ee.Initialize(project='your-project-id')

# MODIS NDVI
collection = ee.ImageCollection('MODIS/061/MOD13Q1') \
    .filterDate('2025-01-01', '2025-12-31') \
    .select('NDVI')

# Sentinel-2 NDVI
s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED') \
    .filterDate('2025-06-01', '2025-09-01') \
    .filterBounds(ee.Geometry.Point([lon, lat]))

def add_ndvi(image):
    return image.addBands(image.normalizedDifference(['B8', 'B4']).rename('NDVI'))

s2_ndvi = s2.map(add_ndvi)
```

**Important (2026):** All noncommercial projects must select a quota tier by April 27, 2026.

---

## 6. TERRAIN / DEM

### 6.1 SRTM 30m (Shuttle Radar Topography Mission)

| Attribute | Details |
|-----------|---------|
| **OpenTopography API** | `https://portal.opentopography.org/API/globaldem?demtype=SRTMGL1&south={S}&north={N}&west={W}&east={E}&outputFormat=GTiff&API_Key={KEY}` |
| **Open Topo Data API** | `https://api.opentopodata.org/v1/srtm30m?locations={lat},{lon}` |
| **NASA Earthdata** | `https://www.earthdata.nasa.gov/` (SRTMGL1 tiles) |
| **Google Earth Engine** | `USGS/SRTMGL1_003` |
| **AWS (NASADEM)** | `s3://nasadem` |
| **Data Format** | GeoTIFF (OpenTopography); SRTMHGT zipped tiles (Earthdata) |
| **Spatial Resolution** | 1 arc-second (~30 m) |
| **Coverage** | 60N to 60S latitude |
| **Vertical Accuracy** | ~16 m absolute; ~6 m relative |
| **Authentication** | OpenTopography: free API key; Earthdata: NASA login |
| **Rate Limits** | OpenTopography: 200/day (academic), 50/day (non-academic); max area: 450,000 km2 |
| **Python Libraries** | `py3dep`, `rasterio`, `elevation`, `bmi-topography` |

**DEM Type Codes (OpenTopography):** `SRTMGL1` (30m), `SRTMGL3` (90m), `SRTMGL1_E` (ellipsoidal).

---

### 6.2 Copernicus DEM GLO-30

| Attribute | Details |
|-----------|---------|
| **OpenTopography API** | `https://portal.opentopography.org/API/globaldem?demtype=COP30&south={S}&north={N}&west={W}&east={E}&outputFormat=GTiff&API_Key={KEY}` |
| **AWS S3 (free, no auth)** | `s3://copernicus-dem-30m` (region: `eu-central-1`) |
| **AWS STAC Catalog** | `https://copernicus-dem-30m-stac.s3.amazonaws.com/` |
| **CDSE STAC API** | `https://stac.dataspace.copernicus.eu/v1/` (collection: `COP-DEM`) |
| **Microsoft Planetary Computer** | `https://planetarycomputer.microsoft.com/dataset/cop-dem-glo-30` |
| **Google Earth Engine** | `COPERNICUS/DEM/GLO30` |
| **Data Format** | Cloud Optimized GeoTIFF |
| **Spatial Resolution** | 1 arc-second (~30 m) |
| **Coverage** | Near-global |
| **Authentication** | AWS: none (`--no-sign-request`); CDSE: account required; OT: API key |
| **Python Libraries** | `pystac-client`, `rasterio`, `boto3`, `rioxarray` |

**AWS CLI Access:**
```bash
aws s3 ls --no-sign-request s3://copernicus-dem-30m/
```

---

### 6.3 ALOS World 3D (AW3D30)

| Attribute | Details |
|-----------|---------|
| **JAXA Portal** | `https://www.eorc.jaxa.jp/ALOS/en/dataset/aw3d30/` |
| **OpenTopography API** | `https://portal.opentopography.org/API/globaldem?demtype=AW3D30&...` |
| **OpenTopography S3** | `aws s3 ls s3://raster/AW3D30/ --recursive --endpoint-url https://opentopography.s3.sdsc.edu --no-sign-request` |
| **Google Earth Engine** | `JAXA/ALOS/AW3D30/V4_1` |
| **Data Format** | GeoTIFF |
| **Spatial Resolution** | 1 arc-second (~30 m) |
| **Coverage** | Global (excluding Antarctica and Japan in some versions) |
| **Authentication** | JAXA: account required; OT: free API key; GEE: Google account |
| **Python Libraries** | `rasterio`, `pystac-client`, `ee` |

---

### 6.4 USGS 3DEP (3D Elevation Program)

| Attribute | Details |
|-----------|---------|
| **3DEP ImageServer** | `https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer` |
| **TNMAccess API** | `https://tnmaccess.nationalmap.gov/api/v1/docs` |
| **OpenTopography API** | `https://portal.opentopography.org/API/usgsdem?demtype=USGS30m&...` |
| **Elevation Point Query** | `https://epqs.nationalmap.gov/v1/docs` |
| **Data Format** | GeoTIFF (Cloud Optimized on AWS), IMG |
| **Spatial Resolution** | 1 m, 1/3 arc-second (~10 m), 1 arc-second (~30 m) |
| **Coverage** | United States |
| **Authentication** | None (ImageServer); OT: API key |
| **Rate Limits** | OT: area limits (1m: 250 km2; 10m: 25,000 km2; 30m: 225,000 km2) |
| **Python Libraries** | `py3dep`, `Seamless3DEP` (HyRiver), `terrainr` |

**DEM Type Codes (OpenTopography):** `USGS1m`, `USGS10m` (1/3 arc-sec), `USGS30m` (1 arc-sec).

---

## 7. WATERSHEDS

### 7.1 HydroSHEDS

| Attribute | Details |
|-----------|---------|
| **Main Website** | `https://www.hydrosheds.org/` |
| **Core Downloads** | `https://www.hydrosheds.org/hydrosheds-core-downloads` |
| **Products Page** | `https://www.hydrosheds.org/products` |
| **Data Format** | Shapefile (vector products), GeoTIFF (raster grids) |
| **Spatial Resolution** | 15 arc-seconds (~500 m) for v1; higher for v2 (TanDEM-X based, releasing 2025) |
| **Coverage** | Global |
| **Authentication** | None (free download from website) |
| **Rate Limits** | N/A (bulk downloads) |
| **Python Libraries** | `geopandas`, `fiona`, `rasterio` |

**Key Products:**
- **HydroBASINS** - Sub-basin boundary polygons (12 levels of nested catchments)
- **HydroRIVERS** - River network line features with attributes
- **HydroLAKES** - Lake shoreline polygons
- **HydroATLAS** - Comprehensive hydro-environmental attributes for basins, rivers, and lakes
- **Core Rasters** - DEM, flow direction, flow accumulation, drainage basins

**Access Method:** Direct download from website by region (continent-level files). No REST API available - static file downloads only.

---

### 7.2 USGS Watershed Boundary Dataset (WBD)

| Attribute | Details |
|-----------|---------|
| **WBD MapServer** | `https://hydro.nationalmap.gov/arcgis/rest/services/wbd/MapServer` |
| **WMS Endpoint** | `https://hydro.nationalmap.gov/arcgis/services/wbd/MapServer/WMSServer?request=GetCapabilities&service=WMS` |
| **WFS Endpoint** | `https://hydro.nationalmap.gov/arcgis/services/wbd/MapServer/WFSServer?request=GetCapabilities&service=WFS` |
| **Download** | `https://apps.nationalmap.gov/downloader/` (The National Map Download Client) |
| **Data Format** | Shapefile, File Geodatabase, WMS/WFS |
| **Spatial Coverage** | US, Puerto Rico, US Virgin Islands |
| **HUC Levels** | 2, 4, 6, 8, 10, 12-digit hydrologic units |
| **Update Frequency** | Quarterly |
| **Authentication** | None |
| **Python Libraries** | `owslib` (WMS/WFS), `geopandas`, `pynhd` (HyRiver suite) |

---

## 8. SPATIAL RISK SURFACES: Multi-Hazard Risk Index Methodology

### 8.1 Research-Backed Approach

The standard methodology for computing multi-hazard risk indices from the datasets above follows a well-established GIS-based workflow documented in peer-reviewed literature:

**Core Formula:**
```
MHR_Index = SUM(w_i * H_i_normalized)

where:
  MHR_Index = Multi-Hazard Risk Index (0-1 or 1-5 scale)
  w_i = weight for hazard layer i (sum of all weights = 1.0)
  H_i_normalized = normalized hazard value for layer i (0-1)
```

### 8.2 Step-by-Step Methodology

**Step 1: Data Acquisition and Preprocessing**
- Acquire hazard layers from the sources documented above
- Reproject all layers to a common CRS (e.g., EPSG:4326 or appropriate UTM zone)
- Resample all rasters to a common spatial resolution (e.g., 250 m or 1 km)
- Align grids using a common extent and cell registration

**Step 2: Normalization (Min-Max Scaling)**
```python
# Min-Max normalization to 0-1 range
H_normalized = (H_raw - H_min) / (H_max - H_min)

# Or reclassification to ordinal scale (1-5):
# 1 = Very Low, 2 = Low, 3 = Medium, 4 = High, 5 = Very High
# Thresholds based on quantiles, natural breaks (Jenks), or domain expertise
```

**Step 3: Weight Assignment**
Methods for determining weights:
1. **Analytic Hierarchy Process (AHP):** Pairwise comparison matrix of hazard importance (Saaty 1980)
2. **Equal Weighting:** All hazards equally weighted (simplest, defensible baseline)
3. **Expert Elicitation:** Domain experts assign relative importance
4. **Principal Component Analysis (PCA):** Data-driven weights from variance

**Step 4: Weighted Overlay Combination**
```python
import rasterio
import numpy as np

# Example: Wildfire + Flood + Drought composite
weights = {'wildfire': 0.35, 'flood': 0.35, 'drought': 0.30}

wildfire_norm = normalize(wildfire_raster)
flood_norm = normalize(flood_raster)
drought_norm = normalize(drought_raster)

risk_surface = (weights['wildfire'] * wildfire_norm +
                weights['flood'] * flood_norm +
                weights['drought'] * drought_norm)
```

**Step 5: Validation**
- Compare against historical disaster records
- Sensitivity analysis varying weights
- Cross-validation with independent hazard assessments

### 8.3 Key Research References

1. **UNDRR (2017)** - "Words into Action: National Disaster Risk Assessment" - Standard framework for multi-hazard risk assessment
2. **Kappes et al. (2012)** - "Challenges of analyzing multi-hazard risk: a review" (Natural Hazards and Earth System Sciences)
3. **Nature Scientific Reports (2024)** - "Global multi-hazard risk assessment in a changing climate" - Uses interaction matrices and weighted overlay
4. **NHESS (2025)** - "Towards multi-hazard and multi-risk indicators - a review and recommendations for development and implementation"

### 8.4 Python Implementation Tools

| Tool | Use Case |
|------|----------|
| `rasterio` + `numpy` | Core raster I/O and array math for overlay |
| `xarray` + `rioxarray` | Multi-dimensional raster analysis with CRS support |
| `geopandas` | Vector-based hazard zone analysis |
| `scikit-learn` | PCA for weight derivation; clustering for risk zones |
| `RiskScape` | Open-source multi-hazard risk modelling engine |
| `rasterstats` | Zonal statistics for risk aggregation |
| `GDAL` | Raster reprojection, resampling, and warping |

### 8.5 Recommended Layer Stack for EcoLens

| Layer | Source | Resolution | Weight (Example) |
|-------|--------|------------|-----------------|
| Active Fire Risk | NASA FIRMS (VIIRS) | 375 m | 0.15 |
| Flood Risk | GloFAS / NOAA NWPS | ~5 km / gauge | 0.15 |
| Drought Severity | US Drought Monitor / SPEI | County / 0.5 deg | 0.15 |
| Vegetation Stress (NDVI anomaly) | MODIS MOD13Q1 / Sentinel-2 | 250 m / 10 m | 0.15 |
| Glacial Retreat Proximity | GLIMS + ITS_LIVE | Variable | 0.10 |
| Terrain Slope Risk | SRTM / Copernicus DEM | 30 m | 0.10 |
| Watershed Vulnerability | HydroSHEDS + WBD | ~500 m | 0.10 |
| Groundwater Depletion | GRACE | 0.25 deg | 0.10 |

---

## 9. QUICK REFERENCE: Python Libraries Summary

```
pip install requests geopandas rasterio xarray rioxarray netCDF4
pip install sentinelhub-py pystac-client earthaccess
pip install cdsapi cfgrib openeo
pip install earthengine-api geemap
pip install py3dep pynhd owslib
pip install zarr boto3 shapely
```

---

## 10. QUICK REFERENCE: Authentication Summary

| Service | Auth Type | Where to Register |
|---------|-----------|-------------------|
| NASA FIRMS | MAP_KEY (email) | `https://firms.modaps.eosdis.nasa.gov/api/map_key/` |
| NASA Earthdata (AppEEARS, GRACE, SRTM) | Earthdata Login | `https://urs.earthdata.nasa.gov/` |
| USGS M2M (Landsat) | Application Token | `https://ers.cr.usgs.gov/profile/access` |
| Copernicus CDSE (Sentinel Hub) | OAuth2 client credentials | `https://dataspace.copernicus.eu/` |
| CEMS EWDS (GloFAS) | Personal access token | `https://ewds.climate.copernicus.eu/` |
| Google Earth Engine | Google account + project | `https://code.earthengine.google.com/register` |
| OpenTopography | API key | `https://portal.opentopography.org/requestService?service=api` |
| NOAA NWPS | None | N/A |
| US Drought Monitor | None | N/A |
| NIFC Fire Perimeters | None | N/A |
| Open-Meteo Flood API | None (non-commercial) | N/A |
| SPEI Database | Login for full download | `https://spei.csic.es/` |
| GLIMS WMS/WFS | None | N/A |
| HydroSHEDS | None | N/A |

---

## Sources

- [NASA FIRMS API](https://firms.modaps.eosdis.nasa.gov/api/)
- [NASA FIRMS Area API](https://firms.modaps.eosdis.nasa.gov/api/area/)
- [NASA FIRMS Data Availability](https://firms.modaps.eosdis.nasa.gov/api/data_availability/)
- [NOAA NWPS API](https://water.noaa.gov/about/api)
- [NOAA NWPS API Docs](https://api.water.noaa.gov/nwps/v1/docs/)
- [US Drought Monitor Web Services](https://droughtmonitor.unl.edu/DmData/DataDownload/WebServiceInfo.aspx)
- [SPEI Database](https://spei.csic.es/database.html)
- [SPEI Global Drought Monitor](https://spei.csic.es/map/)
- [NASA GRACE Data Portal](https://grace.jpl.nasa.gov/data/get-data/)
- [GloFAS Portal](https://global-flood.emergency.copernicus.eu/)
- [CEMS EWDS API Setup](https://ewds.climate.copernicus.eu/how-to-api)
- [Open-Meteo Flood API](https://open-meteo.com/en/docs/flood-api)
- [GFMS - University of Maryland](http://flood.umd.edu/)
- [GLIMS Glacier Database](https://www.glims.org/glacierdata/)
- [Randolph Glacier Inventory 7.0](https://www.glims.org/RGI/)
- [ITS_LIVE](https://its-live.jpl.nasa.gov/)
- [ESA CCI Glaciers](https://climate.esa.int/en/projects/glaciers/data/)
- [Copernicus CDSE APIs](https://documentation.dataspace.copernicus.eu/APIs.html)
- [Copernicus STAC API](https://documentation.dataspace.copernicus.eu/APIs/STAC.html)
- [Sentinel Hub Introduction](https://documentation.dataspace.copernicus.eu/notebook-samples/sentinelhub/introduction_to_SH_APIs.html)
- [AppEEARS API](https://appeears.earthdatacloud.nasa.gov/api/)
- [USGS M2M API](https://m2m.cr.usgs.gov/)
- [Google Earth Engine](https://developers.google.com/earth-engine/)
- [OpenTopography API](https://portal.opentopography.org/apidocs/)
- [OpenTopography Developers](https://opentopography.org/developers)
- [Copernicus DEM on AWS](https://registry.opendata.aws/copernicus-dem/)
- [ALOS AW3D30 JAXA](https://www.eorc.jaxa.jp/ALOS/en/dataset/aw3d30/)
- [USGS 3DEP ImageServer](https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer)
- [TNMAccess API](https://apps.nationalmap.gov/tnmaccess/)
- [HydroSHEDS](https://www.hydrosheds.org/products)
- [USGS WBD MapServer](https://hydro.nationalmap.gov/arcgis/rest/services/wbd/MapServer)
- [NIFC Open Data](https://data-nifc.opendata.arcgis.com/)
- [VIIRS I-Band 375m Active Fire](https://www.earthdata.nasa.gov/data/instruments/viirs/viirs-i-band-375-m-active-fire-data)
- [Multi-Hazard Risk Analysis Methodologies](https://www.anticipation-hub.org/news/multi-hazard-risk-analysis-methodologies)
- [Global Multi-Hazard Risk Assessment (Nature 2024)](https://www.nature.com/articles/s41598-024-55775-2)
- [NHESS Multi-Hazard Indicators Review (2025)](https://nhess.copernicus.org/articles/25/4263/2025/)
- [RiskScape Multi-Hazard Engine](https://link.springer.com/article/10.1007/s11069-022-05593-4)
- [NSIDC Programmatic Access Guide](https://nsidc.org/data/user-resources/help-center/programmatic-data-access-guide)
- [Copernicus DEM on Planetary Computer](https://planetarycomputer.microsoft.com/dataset/cop-dem-glo-30)
