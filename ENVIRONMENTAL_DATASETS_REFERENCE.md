# EcoLens Environmental Datasets Reference
## Comprehensive Free & Public Data Sources (March 2026)

---

# 1. REAL-TIME / NEAR-REAL-TIME APIs

---

## 1.1 AIR QUALITY

### OpenAQ API v3
- **Base URL:** `https://api.openaq.org/v3/`
- **Key Endpoints:**
  - `GET /v3/locations` — list all monitoring stations
  - `GET /v3/locations/{id}/latest` — latest measurements for a station
  - `GET /v3/sensors/{id}/measurements/hourly` — hourly aggregated data
  - `GET /v3/sensors/{id}/days` — daily aggregated data
  - Supports `bbox` parameter for geographic area queries
- **Data Format:** JSON
- **Auth:** Free API key required (register at https://docs.openaq.org/using-the-api/api-key). No key = requests denied.
- **Update Frequency:** Near real-time (varies by station, typically hourly)
- **Coverage:** Global — thousands of stations worldwide
- **Parameters:** PM2.5, PM10, O3, NO2, SO2, CO, BC
- **Docs:** https://docs.openaq.org | Swagger: https://api.openaq.org/docs
- **EcoLens Use:** Global air quality monitoring layer, real-time pollution hotspot visualization

### WAQI (World Air Quality Index) API
- **Base URL:** `https://api.waqi.info/`
- **Key Endpoints:**
  - `GET /feed/{city}/` — AQI for a city
  - `GET /feed/geo:{lat};{lng}/` — AQI by coordinates
  - `GET /feed/here/` — AQI by IP geolocation
  - `GET /map/bounds/?latlng={lat1},{lng1},{lat2},{lng2}` — stations in bounding box
- **Data Format:** JSON
- **Auth:** Free API token required (register at https://aqicn.org/data-platform/token/)
- **Rate Limit:** 1,000 requests/second (generous)
- **Update Frequency:** Real-time (hourly station updates)
- **Coverage:** Global — 11,000+ stations, 1,000+ cities
- **Parameters:** AQI, PM2.5, PM10, NO2, CO, SO2, O3 (individual pollutant AQI)
- **License:** Free for non-commercial; attribution required
- **EcoLens Use:** Quick AQI overlay, health advisory alerts, city-level air quality dashboard

### PurpleAir API
- **Base URL:** `https://api.purpleair.com/v1/`
- **Key Endpoints:**
  - `GET /v1/sensors` — list sensors with filters (bounding box, fields)
  - `GET /v1/sensors/{sensor_id}` — single sensor data
  - Fields: `pm2.5_atm_a`, `pm2.5_atm_b`, `humidity`, `temperature`
- **Data Format:** JSON
- **Auth:** Free API key required (linked to Google account, register at https://develop.purpleair.com/)
- **Rate Limit:** Points-based system (free tier available)
- **Update Frequency:** Real-time (every 2 minutes per sensor)
- **Coverage:** Global but concentrated in North America — crowd-sourced network
- **Resolution:** Point-level (individual sensors)
- **EcoLens Use:** Hyper-local PM2.5 during wildfire events, crowd-sourced supplement to official stations

---

## 1.2 WEATHER / CLIMATE

### Open-Meteo API (TOP RECOMMENDATION — no key needed)
- **Base URL:** `https://api.open-meteo.com/`
- **Key Endpoints:**
  - `GET /v1/forecast` — weather forecast (up to 16 days)
  - `GET /v1/forecast` with `past_days` param — historical + forecast
  - `GET /v1/air-quality` — air quality forecast (PM2.5, PM10, O3, NO2, SO2, CO, dust, pollen, European AQI, US AQI)
  - `GET /v1/flood` — river discharge data (GloFAS)
  - `GET /v1/marine` — marine/ocean weather (wave height, period, direction)
  - `GET /v1/elevation` — elevation data
  - `GET /v1/geocoding` — geocoding search
  - Historical Weather API — data from 1940 to present
  - Climate Change API — CMIP6 climate projections
  - Ensemble API — probabilistic forecasts
  - Seasonal Forecast API — 6-month seasonal outlook
- **Data Format:** JSON, CSV, XLSX
- **Auth:** NONE required (free for non-commercial)
- **Rate Limit:** 10,000 requests/day for non-commercial
- **Update Frequency:** Hourly model updates
- **Coverage:** Global, 1-11 km resolution depending on model
- **Fire-Relevant Variables:** temperature, relative_humidity, wind_speed, wind_direction, precipitation, soil_moisture (all critical for fire weather calculations — you can compute FWI from these)
- **Models:** NOAA GFS+HRRR, DWD ICON, ECMWF IFS, MeteoFrance, JMA, GEM
- **Docs:** https://open-meteo.com/en/docs
- **EcoLens Use:** PRIMARY weather backbone — forecast overlays, drought monitoring via soil moisture, flood warnings via river discharge, fire weather calculations, marine conditions

### NOAA Climate Data Online (CDO) API
- **Base URL:** `https://www.ncei.noaa.gov/cdo-web/api/v2/`
- **Key Endpoints:**
  - `GET /datasets` — available datasets
  - `GET /data` — actual climate data with query params
  - `GET /stations` — station metadata
  - `GET /locations` — location metadata
- **Data Format:** JSON
- **Auth:** Free token required (request at https://www.ncdc.noaa.gov/cdo-web/token)
- **Rate Limit:** 5 requests/second, 10,000/day
- **Update Frequency:** Historical data; updated periodically
- **Coverage:** Global station network (GHCN-Daily, etc.)
- **Note:** The legacy endpoint is being superseded by `https://www.ncei.noaa.gov/access/services/data/v1`
- **EcoLens Use:** Historical climate baseline data, station observations for validation

### NASA FIRMS (Fire Information for Resource Management System)
- **Base URL:** `https://firms.modaps.eosdis.nasa.gov/api/`
- **Key Endpoints:**
  - `GET /api/area/csv/{MAP_KEY}/{source}/{area}/{days}` — active fires in area (CSV)
  - `GET /api/area/json/{MAP_KEY}/{source}/{area}/{days}` — active fires (JSON)
  - Sources: `MODIS_NRT`, `VIIRS_SNPP_NRT`, `VIIRS_NOAA20_NRT`, `VIIRS_NOAA21_NRT`, `LANDSAT_NRT`
- **Data Format:** CSV, JSON, KML, SHP
- **Auth:** Free MAP_KEY required (register at https://firms.modaps.eosdis.nasa.gov/api/map_key/)
- **Rate Limit:** 5,000 transactions per 10 minutes
- **Update Frequency:** Ultra real-time (<60 seconds for US/Canada), NRT (<3 hours globally)
- **Coverage:** Global
- **Resolution:** 375m (VIIRS), 1km (MODIS), 30m (Landsat)
- **Data since:** MODIS from Nov 2000, VIIRS S-NPP from Jan 2012, NOAA-20 from Apr 2018, NOAA-21 from Jan 2024
- **EcoLens Use:** CRITICAL — real-time wildfire detection layer, active fire tracking, fire perimeter estimation

---

## 1.3 OCEAN / MARINE

### Global Fishing Watch API
- **Base URL:** `https://gateway.api.globalfishingwatch.org/`
- **Key Endpoints:**
  - Vessel search and tracking
  - Apparent fishing activity (AIS-derived)
  - Vessel events (loitering, port visits, encounters)
  - Insights API — IUU fishing risk indicators
  - Map tiling for visualization
- **Data Format:** JSON, GeoJSON
- **Auth:** Free API token required (register at https://globalfishingwatch.org/our-apis/)
- **Update Frequency:** Near real-time (AIS-based, hours to days latency)
- **Coverage:** Global oceans
- **License:** Non-commercial use only, CC-BY-SA 4.0
- **Python SDK:** Released April 2025 (`gfwr` package)
- **Docs:** https://globalfishingwatch.org/our-apis/documentation
- **EcoLens Use:** Illegal fishing detection layer, marine activity monitoring, ocean sustainability dashboard

### NOAA Coral Reef Watch (via ERDDAP)
- **ERDDAP Endpoints (no auth, REST-based):**
  - `https://coastwatch.noaa.gov/erddap/griddap/noaacrwsstDaily.json` — Daily SST (CoralTemp)
  - `https://oceanwatch.pifsc.noaa.gov/erddap/griddap/CRW_sst_anom_v1_0.json` — SST Anomaly
  - `https://oceanwatch.pifsc.noaa.gov/erddap/griddap/CRW_sst_v3_1_monthly.json` — Monthly SST v3.1
  - Query with lat/lon/time constraints appended to URL
- **Data Format:** JSON, CSV, NetCDF, GeoTIFF (via ERDDAP)
- **Auth:** NONE required
- **Update Frequency:** Daily (5km resolution)
- **Coverage:** Global oceans, 1985-present
- **Products:** SST, SST Anomaly, Coral Bleaching HotSpot, Degree Heating Week (DHW), Bleaching Alert Area (7-day max), SST Trend
- **Alert Levels:** No Stress, Watch, Warning, Alert Level 1, Alert Level 2
- **EcoLens Use:** Coral bleaching risk visualization, ocean heat monitoring, marine ecosystem health dashboard

### Copernicus Marine Service (CMEMS)
- **Data Store:** https://data.marine.copernicus.eu/products
- **API:** Python Copernicus Marine Toolbox (`pip install copernicusmarine`)
- **Auth:** Free account required (register at https://data.marine.copernicus.eu/register)
- **Data Format:** NetCDF, Zarr
- **Update Frequency:** Daily to monthly depending on product
- **Coverage:** Global oceans
- **Products:** SST, salinity, currents, sea level, ocean color, biogeochemistry, sea ice, waves, wind
- **New 2025:** Coastal bathymetry, Sargassum floating algae index, SWOT sea surface height
- **EcoLens Use:** Comprehensive ocean data backbone — currents, sea level, temperature, salinity layers

---

## 1.4 EARTHQUAKES / VOLCANOES

### USGS Earthquake API (NO KEY NEEDED)
- **Real-time GeoJSON Feeds (recommended for apps):**
  - `https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson` — all earthquakes, past hour
  - `https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson` — past day
  - `https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_week.geojson` — past week
  - `https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_month.geojson` — past month
  - Replace `all` with `significant`, `4.5`, `2.5`, `1.0` for magnitude filters
- **Query API:**
  - `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=YYYY-MM-DD&endtime=YYYY-MM-DD&minmagnitude=X`
  - Supports: lat/lon, radius, depth, magnitude range, time range
- **Data Format:** GeoJSON (FeatureCollection)
- **Auth:** NONE
- **Rate Limit:** No documented limit (use feeds for best performance)
- **Update Frequency:** Real-time (feeds update every minute for "all" feeds)
- **Coverage:** Global
- **Properties:** magnitude, place, time, coordinates, depth, tsunami flag, felt reports, alert level
- **Docs:** https://earthquake.usgs.gov/fdsnws/event/1/
- **EcoLens Use:** Real-time earthquake layer, seismic activity visualization, tsunami warning integration

### USGS Volcano Hazards API (NO KEY NEEDED)
- **Base URL:** `https://volcanoes.usgs.gov/hans-public/api/volcano/`
- **Key Endpoints (all return JSON):**
  - `getElevatedVolcanoes` — all volcanoes with elevated alert status (yellow/orange/red)
  - `getCapElevated` — CAP protocol data for highly elevated volcanoes (orange/red + watch/warning)
  - `getMonitoredVolcanoes` — all USGS-monitored volcanoes
  - `getUSVolcanoes` — all US volcanoes
  - `getVolcano/{vnumOrVolcanoCd}` — specific volcano info
  - `newestForVolcano/{vnumOrVolcanoCd}` — latest notice for a volcano
- **Data Format:** JSON (except `getSocialMediaRSS` which is XML)
- **Auth:** NONE
- **Update Frequency:** Real-time alerts
- **Coverage:** US volcanoes (161 monitored), links to Smithsonian for global
- **Alert Levels:** Normal, Advisory, Watch, Warning | Colors: Green, Yellow, Orange, Red
- **EcoLens Use:** Volcanic eruption alerts, hazard status dashboard, multi-hazard monitoring

### Smithsonian Global Volcanism Program
- **Website:** https://volcano.si.edu/
- **Data Access:**
  - Weekly Volcanic Activity Report: https://volcano.si.edu/reports_weekly.cfm
  - Daily Volcanic Activity Report: https://volcano.si.edu/reports_daily.cfm (launched Aug 2025)
  - Current Eruptions: https://volcano.si.edu/gvp_currenteruptions.cfm
  - Database search: https://volcano.si.edu/search_volcano.cfm
  - Holocene volcano list (XML/Excel download): https://volcano.si.edu/volcanolist_holocene.cfm
- **Data Format:** XML/Excel download, HTML reports
- **Auth:** NONE
- **Update Frequency:** Daily (Mon-Fri) and weekly reports
- **Coverage:** Global — all ~1,400+ Holocene volcanoes, ~45 with continuing eruptions
- **Database Version:** v5.3.4 (Dec 2025)
- **EcoLens Use:** Global volcano database, eruption history, weekly/daily activity reports

---

## 1.5 CARBON / EMISSIONS

### Climate TRACE
- **Data Portal:** https://climatetrace.org/data
- **API (Beta):** Available for expert users
  - Search emitting assets by sector, owner, location
  - Query emissions and asset details
  - Lookup aggregated emissions by country
- **Data Format:** CSV (download), JSON (API)
- **Auth:** Free (beta API may require registration)
- **Update Frequency:** Monthly emissions with ~2 months latency; annual summaries
- **Coverage:** Global, country-level and source-level
- **Time Range:** Annual 2015-2024, monthly 2021-2024, estimated 2025
- **License:** Creative Commons 4.0
- **EcoLens Use:** Emissions tracking by sector/country, climate accountability dashboard

### Carbon Monitor
- **Website:** https://carbonmonitor.org/
- **Cities Portal:** https://cities.carbonmonitor.org/
- **Data Access:** Free download from website (CSV files)
- **Auth:** NONE (open data)
- **Update Frequency:** Near-daily CO2 emissions estimates
- **Coverage:** Global, national level, 416 cities
- **Time Range:** January 2019 to present
- **Sectors:** Power, industry, ground transport, aviation, residential, international shipping
- **Data Sources:** Hourly power generation, monthly production indices, daily mobility data
- **EcoLens Use:** Daily CO2 emissions tracking, sector-level breakdowns, city carbon footprint comparison

### Emissions API (Self-hosted)
- **Note:** Public service shut down July 2024, but code is open-source on GitHub
- **GitHub:** https://github.com/emissions-api/emissions-api
- **Data Source:** ESA Sentinel-5P satellite
- **Parameters:** Carbon monoxide, methane
- **EcoLens Use:** Can self-host for satellite-based CO/CH4 monitoring

---

## 1.6 BIODIVERSITY / SPECIES

### GBIF (Global Biodiversity Information Facility) API
- **Base URL:** `https://api.gbif.org/v1/`
- **Key Endpoints:**
  - `GET /v1/occurrence/search?taxonKey=X&country=XX` — search occurrences
  - `GET /v1/species/match?name=Passer%20domesticus` — species name matching
  - `GET /v1/species/{key}` — species details
  - `GET /v1/species/{key}/distributions` — species distribution
  - `GET /v1/occurrence/download` — async bulk downloads (POST request)
- **Data Format:** JSON (API), DwC-A (downloads)
- **Auth:** NONE for search queries; free account for downloads
- **Update Frequency:** Continuously updated
- **Coverage:** Global — 3.1+ billion occurrence records from 2,500+ institutions
- **API Version:** Stable v1
- **Docs:** https://techdocs.gbif.org/en/openapi/
- **EcoLens Use:** Biodiversity mapping, species occurrence visualization, ecological impact assessment

### IUCN Red List API
- **Base URL:** `https://apiv3.iucnredlist.org/api/v3/`
- **Key Endpoints:**
  - `/api/v3/species/{name}` — species by name
  - `/api/v3/species/region/{region_identifier}` — species by region
  - `/api/v3/threats/species/name/{name}` — threats to species
  - `/api/v3/species/country/getspecies/{country}` — species by country
- **Data Format:** JSON
- **Auth:** Free API key required (register at https://api.iucnredlist.org/users/sign_up)
- **Update Frequency:** Updated periodically (latest: version 2025-1, March 2025)
- **Coverage:** Global — 160,000+ species assessed
- **Docs:** https://api.iucnredlist.org/api-docs/index.html
- **EcoLens Use:** Endangered species overlay, conservation status visualization, biodiversity risk assessment

### eBird API 2.0
- **Base URL:** `https://api.ebird.org/v2/`
- **Key Endpoints:**
  - `GET /v2/data/obs/{regionCode}/recent` — recent observations in region
  - `GET /v2/data/obs/geo/recent?lat=X&lng=X` — recent observations by location
  - `GET /v2/product/spplist/{regionCode}` — species list for region
  - `GET /v2/ref/hotspot/geo?lat=X&lng=X` — birding hotspots near location
  - `GET /v2/data/obs/{regionCode}/recent/{speciesCode}` — recent sightings of specific species
- **Data Format:** JSON
- **Auth:** Free API key required (register at https://ebird.org/api/keygen)
- **Rate Limit:** Limited to recent/summary data via API
- **Update Frequency:** Real-time (citizen science submissions)
- **Coverage:** Global — largest biodiversity citizen science dataset
- **Bulk Data:** eBird Basic Dataset (EBD) available for download (monthly updates on 15th)
- **Docs:** https://documenter.getpostman.com/view/664302/S1ENwy59
- **EcoLens Use:** Bird observation mapping, citizen science layer, migration tracking, biodiversity indicators

---

## 1.7 SOIL / LAND

### SoilGrids REST API
- **Base URL:** `https://rest.isric.org/soilgrids/v2.0/`
- **Key Endpoints:**
  - `GET /properties/query?lon=X&lat=X&property=clay&depth=0-5cm` — point query
  - Properties: clay, sand, silt, nitrogen, SOC, pH, CEC, bulk density, etc.
  - Depths: 0-5cm, 5-15cm, 15-30cm, 30-60cm, 60-100cm, 100-200cm
- **Data Format:** JSON
- **Auth:** NONE
- **Rate Limit:** 5 API calls per minute (fair use)
- **Coverage:** Global, 250m resolution
- **Status:** Beta — occasional downtime. Alternative: download GeoTIFF tiles from https://soilgrids.org/
- **License:** CC-BY 4.0
- **Docs:** https://rest.isric.org/soilgrids/v2.0/docs
- **EcoLens Use:** Soil property mapping for drought/agriculture analysis, erosion risk, land degradation

### ESA WorldCover
- **Download Portal:** https://esa-worldcover.org/en/data-access
- **AWS Open Data:** `s3://esa-worldcover` (eu-central-1)
- **Google Earth Engine:** `ee.ImageCollection("ESA/WorldCover/v200")`
- **Data Format:** Cloud-Optimized GeoTIFF (COG), WGS84, 1x1 degree tiles
- **Auth:** NONE (direct download or AWS)
- **Resolution:** 10m
- **Coverage:** Global land cover for 2020 & 2021
- **Classes:** 11 land cover classes (tree cover, shrubland, grassland, cropland, built-up, bare/sparse, snow/ice, water, wetland, mangroves, moss/lichen)
- **License:** CC-BY 4.0
- **EcoLens Use:** Land cover classification layer, deforestation detection baseline, urban expansion tracking

---

## 1.8 SEA LEVEL / ICE

### NASA Sea Level Change Portal
- **Portal:** https://sealevel.nasa.gov/data
- **Data Analysis Tool:** https://sealevel.nasa.gov/data-analysis-tool/
- **IPCC Projection Tool:** https://sealevel.nasa.gov/ipcc-ar6-sea-level-projection-tool
- **Statistics API:** https://sealevel-nexus.jpl.nasa.gov/ (JSON/CSV output)
- **Auth:** NONE
- **Coverage:** Global
- **Data:** Satellite altimetry sea level measurements, projections
- **EcoLens Use:** Sea level rise visualization, coastal flooding risk assessment, IPCC projection overlays

### NSIDC Sea Ice Index
- **Portal:** https://nsidc.org/data/g02135/versions/4
- **Data Download:** CSV, Excel, GeoTIFF, PNG browse images
- **Interactive Tool:** https://nsidc.org/sea-ice-today/sea-ice-tools/charctic-interactive-sea-ice-graph
- **Auth:** NONE
- **Update Frequency:** Daily and monthly products
- **Coverage:** Arctic and Antarctic, 1978-present
- **Resolution:** 25 km (based on passive microwave satellite data)
- **Note:** Reduced services from Oct 2025 due to funding cuts
- **Data Fields:** Sea ice extent, concentration, area, anomalies
- **EcoLens Use:** Ice extent tracking, Jakobshavn/Greenland context data, climate change visualization

---

# 2. HISTORICAL DATASETS (Downloadable)

---

### ERA5 (ECMWF Reanalysis v5)
- **Access:** Copernicus Climate Data Store — https://cds.climate.copernicus.eu/
- **API:** `cdsapi` Python package (`pip install cdsapi`)
- **Auth:** Free CDS account required (personal API token from https://cds.climate.copernicus.eu/user/profile)
- **Data Format:** NetCDF, GRIB
- **Resolution:** 31 km global grid, 137 vertical levels
- **Time Range:** 1940 to present (2-5 day latency)
- **Update Frequency:** Daily updates (near real-time ERA5T available)
- **Variables:** 200+ atmospheric, land, ocean wave variables (temperature, precipitation, wind, humidity, soil moisture, surface radiation, etc.)
- **EcoLens Use:** Historical weather reanalysis for any location, baseline climate data, fire weather reconstruction

### CHIRPS (Climate Hazards InfraRed Precipitation with Stations)
- **Download:** https://www.chc.ucsb.edu/data/chirps
- **Google Earth Engine:** `UCSB-CHG/CHIRPS/DAILY` and `UCSB-CHG/CHIRPS/PENTAD`
- **AWS:** Digital Earth Africa mirror for Africa
- **Data Format:** GeoTIFF, NetCDF, BIL
- **Auth:** NONE (public domain)
- **Resolution:** 0.05 degrees (~5.5 km)
- **Time Range:** 1981 to present (daily)
- **Coverage:** Quasi-global land (50S-50N)
- **Version:** v3 released Jan 2025 (v2 production ends Dec 2026)
- **EcoLens Use:** CRITICAL for drought monitoring — long-term precipitation trends, drought index calculations, rainfall anomaly mapping

### MODIS Burned Area (MCD64A1)
- **Download:** https://ladsweb.modaps.eosdis.nasa.gov/
- **Also via:** LP DAAC (https://lpdaac.usgs.gov/products/mcd64a1v061/)
- **Google Earth Engine:** `MODIS/061/MCD64A1`
- **Data Format:** HDF, GeoTIFF, Shapefile
- **Auth:** Free NASA Earthdata login
- **Resolution:** 500m
- **Time Range:** November 2000 to present (monthly)
- **Version:** v6.1 (current)
- **Variables:** Burn date, confidence, first/last day of burn
- **EcoLens Use:** Historical fire perimeter mapping, burned area statistics, fire regime analysis

### Hansen Global Forest Change (2000-2024)
- **Download:** https://storage.googleapis.com/earthenginepartners-hansen/GFC-2024-v1.12/download.html
- **Google Earth Engine:** `UMD/hansen/global_forest_change_2024_v1_12`
- **Web Viewer:** https://glad.earthengine.app/view/global-forest-change
- **Data Format:** GeoTIFF (10x10 degree tiles)
- **Auth:** NONE (direct download)
- **Resolution:** 30m (Landsat-derived)
- **Time Range:** 2000-2024 (annual updates)
- **Version:** v1.12 (latest)
- **Layers:** Tree cover 2000 (%), annual tree cover loss, tree cover gain, loss year, data mask
- **File Sizes:** Loss/gain/lossyear ~10 GB each globally; treecover2000 ~50 GB
- **EcoLens Use:** CRITICAL — deforestation tracking, forest loss visualization by year, forest cover change analysis

### Landsat Analysis Ready Data
- **Access:** USGS EarthExplorer (https://earthexplorer.usgs.gov/) or Google Earth Engine
- **Auth:** Free USGS account
- **Data Format:** GeoTIFF
- **Resolution:** 30m (multispectral), 15m (panchromatic)
- **Time Range:** 1972-present (Landsat 1-9)
- **Coverage:** Global
- **EcoLens Use:** Long-term land change analysis, NDVI time series, burn scar mapping

---

# 3. DATASETS FOR 3D SIMULATIONS

---

## 3.1 CAMP FIRE SIMULATION

### MTBS (Monitoring Trends in Burn Severity)
- **Download Portal:** https://www.mtbs.gov/direct-download
- **Google Earth Engine:** `USFS/GTAC/MTBS/annual_burn_severity_mosaics/v1`
- **Microsoft Planetary Computer:** Also available
- **Data Format:** GeoTIFF (burn severity), Shapefile (fire perimeters)
- **Auth:** NONE
- **Coverage:** US fires 1984-2024, all lands
- **Version:** v12.0 (April 2025)
- **Burn Severity Classes:** Unburned, low, moderate, high severity + increased greenness
- **EcoLens Use:** CRITICAL — actual Camp Fire burn severity map at 30m for 3D simulation ground truth

### CAL FIRE FRAP Data
- **GIS Data Download:** https://frap.fire.ca.gov/mapping/gis-data/
- **California Open Data (Camp Fire specific):**
  - Fire Perimeters: https://data.ca.gov/dataset/california-fire-perimeters-all
  - Camp Fire Structure Status: https://data.ca.gov/dataset/camp-fire-structure-status
- **ArcGIS Hub:** https://hub-calfire-forestry.hub.arcgis.com/
- **Data Format:** Shapefile, GeoJSON, CSV, KML, GeoTIFF, PNG
- **APIs:** GeoServices, WMS, WFS
- **Auth:** NONE
- **Coverage:** California wildland fires
- **EcoLens Use:** Camp Fire perimeter, structure damage data, ignition point, progression mapping for simulation

### USGS Post-Fire Debris Flow Hazard Assessment
- **Dashboard:** https://www.arcgis.com/apps/dashboards/c09fa874362e48a9afe79432f2efe6fe
- **Data:** https://www.usgs.gov/data/2013-2023-post-wildfire-debris-flow-hazard-assessments
- **Interactive Tool:** https://landslides.usgs.gov/hazards/postfire_debrisflow/
- **Data Format:** Shapefile, geodatabase
- **Auth:** NONE
- **Coverage:** Western US fires 2013-2024
- **Variables:** Debris flow probability, estimated volume, combined hazard
- **Methodology:** Basin morphometry + burn severity + soil properties + rainfall characteristics
- **EcoLens Use:** Post-Camp Fire debris flow hazard overlay for simulation, secondary hazard visualization

---

## 3.2 JAKOBSHAVN GLACIER SIMULATION

### BedMachine Greenland
- **NSIDC Access:** https://nsidc.org/data/IDBMG4
- **Latest Version:** v5 (DOI: 10.5067/GMEVBWFLWA7X)
- **NASA Open Data:** https://data.nasa.gov/dataset/icebridge-bedmachine-greenland-v005
- **Data Format:** NetCDF
- **Auth:** Free NASA Earthdata login
- **Resolution:** 150m
- **Coverage:** Entire Greenland ice sheet
- **Variables:** Ice thickness, bed topography, surface elevation, ice/ocean/land mask, error estimates
- **Method:** Mass conservation + multi-beam bathymetry
- **EcoLens Use:** CRITICAL — ice thickness and bed topography for Jakobshavn 3D glacier simulation

### NASA MEaSUREs Greenland Ice Velocity
- **NSIDC Access:** https://nsidc.org/data/nsidc-0478
- **Data Format:** GeoTIFF, NetCDF
- **Auth:** Free NASA Earthdata login
- **Coverage:** Greenland ice sheet, all major outlet glaciers
- **Resolution:** 200-500m
- **Time Range:** Seasonal/annual velocity maps
- **Variables:** Ice velocity (vx, vy), speed, error
- **EcoLens Use:** Jakobshavn velocity data for flow simulation, calving dynamics

### OMG (Oceans Melting Greenland) Bathymetry
- **PO.DAAC Access:** https://podaac.jpl.nasa.gov/omg
- **MBES Data:** DOI 10.5067/OMGEV-MBES1
- **SBES Data:** DOI 10.5067/OMGEV-SBES1
- **Data Format:** NetCDF
- **Auth:** Free NASA Earthdata login
- **Coverage:** Greenland fjords and coastal waters
- **Resolution:** High-resolution (MBES) and supplementary (SBES)
- **Variables:** Bathymetry at glacier termini, fjord depth
- **EcoLens Use:** Underwater topography around Jakobshavn for ocean-glacier interaction simulation

---

# 4. QUICK-START PRIORITY LIST

These datasets can be integrated fastest (no or trivial auth, simple REST/GeoJSON):

| Priority | Dataset | Auth | Format | Effort |
|----------|---------|------|--------|--------|
| 1 | USGS Earthquake API | NONE | GeoJSON | Trivial — just fetch URL |
| 2 | USGS Volcano API | NONE | JSON | Trivial — just fetch URL |
| 3 | Open-Meteo (weather+AQ+flood) | NONE | JSON | Trivial — query params |
| 4 | NOAA Coral Reef Watch (ERDDAP) | NONE | JSON/CSV | Easy — ERDDAP URL builder |
| 5 | WAQI Air Quality | Free token | JSON | Easy — simple registration |
| 6 | NASA FIRMS Active Fire | Free MAP_KEY | JSON/CSV | Easy — critical for wildfires |
| 7 | OpenAQ Air Quality | Free key | JSON | Easy — register online |
| 8 | GBIF Biodiversity | NONE (search) | JSON | Easy — v1 API stable |
| 9 | Hansen Forest Change | NONE | GeoTIFF | Medium — large tiles, GEE best |
| 10 | ESA WorldCover | NONE | COG/GeoTIFF | Medium — large tiles, AWS/GEE |

---

# 5. API CODE SNIPPETS (Quick Reference)

```
# USGS Earthquakes — past day, magnitude 2.5+
GET https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson

# USGS Volcanoes — all elevated
GET https://volcanoes.usgs.gov/hans-public/api/volcano/getElevatedVolcanoes

# Open-Meteo — weather + fire-relevant vars
GET https://api.open-meteo.com/v1/forecast?latitude=39.76&longitude=-121.62&hourly=temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation&daily=temperature_2m_max,temperature_2m_min

# Open-Meteo — air quality
GET https://api.open-meteo.com/v1/air-quality?latitude=39.76&longitude=-121.62&hourly=pm2_5,pm10,us_aqi

# Open-Meteo — flood (river discharge)
GET https://flood-api.open-meteo.com/v1/flood?latitude=39.76&longitude=-121.62&daily=river_discharge

# NOAA Coral Reef Watch — SST via ERDDAP
GET https://coastwatch.noaa.gov/erddap/griddap/noaacrwsstDaily.json?analysed_sst[(last)][(30):(50)][(-130):(-110)]

# WAQI — AQI by coordinates (replace TOKEN)
GET https://api.waqi.info/feed/geo:39.76;-121.62/?token=YOUR_TOKEN

# GBIF — species occurrence search
GET https://api.gbif.org/v1/occurrence/search?taxonKey=2480498&country=US&limit=20

# NASA FIRMS — active fires in bounding box
GET https://firms.modaps.eosdis.nasa.gov/api/area/json/YOUR_MAP_KEY/VIIRS_SNPP_NRT/-130,30,-110,50/1
```

---

# 6. SUMMARY TABLE

| Category | Dataset | Real-time? | Free? | API? | Key Needed? |
|----------|---------|-----------|-------|------|-------------|
| Air Quality | OpenAQ v3 | Yes | Yes | REST | Yes (free) |
| Air Quality | WAQI | Yes | Yes | REST | Yes (free) |
| Air Quality | PurpleAir | Yes | Yes | REST | Yes (free) |
| Weather | Open-Meteo | Yes | Yes | REST | No |
| Weather | NOAA CDO | No (historical) | Yes | REST | Yes (free) |
| Fire | NASA FIRMS | Yes | Yes | REST | Yes (free) |
| Ocean | Global Fishing Watch | Near-RT | Yes | REST | Yes (free) |
| Ocean | NOAA Coral Reef Watch | Daily | Yes | ERDDAP | No |
| Ocean | Copernicus Marine | Daily | Yes | Python | Yes (free) |
| Earthquake | USGS Earthquake | Yes | Yes | REST | No |
| Volcano | USGS Volcano | Yes | Yes | REST | No |
| Volcano | Smithsonian GVP | Daily | Yes | Web/XML | No |
| Carbon | Climate TRACE | Monthly | Yes | REST (beta) | TBD |
| Carbon | Carbon Monitor | Daily | Yes | Download | No |
| Biodiversity | GBIF | Continuous | Yes | REST | No (search) |
| Biodiversity | IUCN Red List | Periodic | Yes | REST | Yes (free) |
| Biodiversity | eBird | Real-time | Yes | REST | Yes (free) |
| Soil | SoilGrids | Static | Yes | REST (beta) | No |
| Land Cover | ESA WorldCover | Static | Yes | Download/AWS | No |
| Sea Level | NASA Sea Level | Periodic | Yes | REST/Download | No |
| Sea Ice | NSIDC Sea Ice Index | Daily | Yes | Download | No |
| Historical | ERA5 | 2-5 day lag | Yes | Python (cdsapi) | Yes (free) |
| Historical | CHIRPS | ~Monthly | Yes | Download/GEE | No |
| Historical | MODIS Burned Area | Monthly | Yes | Download/GEE | Yes (free) |
| Historical | Hansen Forest Change | Annual | Yes | Download/GEE | No |
| Simulation | MTBS Burn Severity | Annual | Yes | Download/GEE | No |
| Simulation | CAL FIRE FRAP | Periodic | Yes | Download/WFS | No |
| Simulation | BedMachine Greenland | Static (v5) | Yes | Download | Yes (free) |
| Simulation | MEaSUREs Ice Velocity | Seasonal | Yes | Download | Yes (free) |
| Simulation | OMG Bathymetry | Static | Yes | Download | Yes (free) |
