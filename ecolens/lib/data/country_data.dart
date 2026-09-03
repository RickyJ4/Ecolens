// ═══════════════════════════════════════════════════════════════
// COUNTRY DATA
// Static mapping of countries: code, iso3, name, lat, lon, region
// Covers all G20, EU, ASEAN, SIDS, African Union, and more (~200)
// ═══════════════════════════════════════════════════════════════

class CountryInfo {
  final String code;   // ISO 3166-1 alpha-2
  final String iso3;   // ISO 3166-1 alpha-3
  final String name;
  final double lat;
  final double lon;
  final String region;

  const CountryInfo({
    required this.code,
    required this.iso3,
    required this.name,
    required this.lat,
    required this.lon,
    required this.region,
  });
}

/// All countries indexed by ISO alpha-2 code (lowercase).
final Map<String, CountryInfo> allCountries = {
  // ── AFRICA ──────────────────────────────────────────────
  'dz': const CountryInfo(code: 'dz', iso3: 'DZA', name: 'Algeria', lat: 28.03, lon: 1.66, region: 'Africa'),
  'ao': const CountryInfo(code: 'ao', iso3: 'AGO', name: 'Angola', lat: -11.20, lon: 17.87, region: 'Africa'),
  'bj': const CountryInfo(code: 'bj', iso3: 'BEN', name: 'Benin', lat: 9.31, lon: 2.32, region: 'Africa'),
  'bw': const CountryInfo(code: 'bw', iso3: 'BWA', name: 'Botswana', lat: -22.33, lon: 24.68, region: 'Africa'),
  'bf': const CountryInfo(code: 'bf', iso3: 'BFA', name: 'Burkina Faso', lat: 12.24, lon: -1.56, region: 'Africa'),
  'bi': const CountryInfo(code: 'bi', iso3: 'BDI', name: 'Burundi', lat: -3.37, lon: 29.92, region: 'Africa'),
  'cv': const CountryInfo(code: 'cv', iso3: 'CPV', name: 'Cabo Verde', lat: 16.00, lon: -24.01, region: 'Africa'),
  'cm': const CountryInfo(code: 'cm', iso3: 'CMR', name: 'Cameroon', lat: 7.37, lon: 12.35, region: 'Africa'),
  'cf': const CountryInfo(code: 'cf', iso3: 'CAF', name: 'Central African Republic', lat: 6.61, lon: 20.94, region: 'Africa'),
  'td': const CountryInfo(code: 'td', iso3: 'TCD', name: 'Chad', lat: 15.45, lon: 18.73, region: 'Africa'),
  'km': const CountryInfo(code: 'km', iso3: 'COM', name: 'Comoros', lat: -11.88, lon: 43.87, region: 'Africa'),
  'cg': const CountryInfo(code: 'cg', iso3: 'COG', name: 'Congo', lat: -0.23, lon: 15.83, region: 'Africa'),
  'cd': const CountryInfo(code: 'cd', iso3: 'COD', name: 'DR Congo', lat: -4.04, lon: 21.76, region: 'Africa'),
  'ci': const CountryInfo(code: 'ci', iso3: 'CIV', name: "Cote d'Ivoire", lat: 7.54, lon: -5.55, region: 'Africa'),
  'dj': const CountryInfo(code: 'dj', iso3: 'DJI', name: 'Djibouti', lat: 11.83, lon: 42.59, region: 'Africa'),
  'eg': const CountryInfo(code: 'eg', iso3: 'EGY', name: 'Egypt', lat: 26.82, lon: 30.80, region: 'Africa'),
  'gq': const CountryInfo(code: 'gq', iso3: 'GNQ', name: 'Equatorial Guinea', lat: 1.65, lon: 10.27, region: 'Africa'),
  'er': const CountryInfo(code: 'er', iso3: 'ERI', name: 'Eritrea', lat: 15.18, lon: 39.78, region: 'Africa'),
  'sz': const CountryInfo(code: 'sz', iso3: 'SWZ', name: 'Eswatini', lat: -26.52, lon: 31.47, region: 'Africa'),
  'et': const CountryInfo(code: 'et', iso3: 'ETH', name: 'Ethiopia', lat: 9.15, lon: 40.49, region: 'Africa'),
  'ga': const CountryInfo(code: 'ga', iso3: 'GAB', name: 'Gabon', lat: -0.80, lon: 11.61, region: 'Africa'),
  'gm': const CountryInfo(code: 'gm', iso3: 'GMB', name: 'Gambia', lat: 13.44, lon: -15.31, region: 'Africa'),
  'gh': const CountryInfo(code: 'gh', iso3: 'GHA', name: 'Ghana', lat: 7.95, lon: -1.02, region: 'Africa'),
  'gn': const CountryInfo(code: 'gn', iso3: 'GIN', name: 'Guinea', lat: 9.95, lon: -9.70, region: 'Africa'),
  'gw': const CountryInfo(code: 'gw', iso3: 'GNB', name: 'Guinea-Bissau', lat: 11.80, lon: -15.18, region: 'Africa'),
  'ke': const CountryInfo(code: 'ke', iso3: 'KEN', name: 'Kenya', lat: -0.02, lon: 37.91, region: 'Africa'),
  'ls': const CountryInfo(code: 'ls', iso3: 'LSO', name: 'Lesotho', lat: -29.61, lon: 28.23, region: 'Africa'),
  'lr': const CountryInfo(code: 'lr', iso3: 'LBR', name: 'Liberia', lat: 6.43, lon: -9.43, region: 'Africa'),
  'ly': const CountryInfo(code: 'ly', iso3: 'LBY', name: 'Libya', lat: 26.34, lon: 17.23, region: 'Africa'),
  'mg': const CountryInfo(code: 'mg', iso3: 'MDG', name: 'Madagascar', lat: -18.77, lon: 46.87, region: 'Africa'),
  'mw': const CountryInfo(code: 'mw', iso3: 'MWI', name: 'Malawi', lat: -13.25, lon: 34.30, region: 'Africa'),
  'ml': const CountryInfo(code: 'ml', iso3: 'MLI', name: 'Mali', lat: 17.57, lon: -4.00, region: 'Africa'),
  'mr': const CountryInfo(code: 'mr', iso3: 'MRT', name: 'Mauritania', lat: 21.01, lon: -10.94, region: 'Africa'),
  'mu': const CountryInfo(code: 'mu', iso3: 'MUS', name: 'Mauritius', lat: -20.35, lon: 57.55, region: 'Africa'),
  'ma': const CountryInfo(code: 'ma', iso3: 'MAR', name: 'Morocco', lat: 31.79, lon: -7.09, region: 'Africa'),
  'mz': const CountryInfo(code: 'mz', iso3: 'MOZ', name: 'Mozambique', lat: -18.67, lon: 35.53, region: 'Africa'),
  'na': const CountryInfo(code: 'na', iso3: 'NAM', name: 'Namibia', lat: -22.96, lon: 18.49, region: 'Africa'),
  'ne': const CountryInfo(code: 'ne', iso3: 'NER', name: 'Niger', lat: 17.61, lon: 8.08, region: 'Africa'),
  'ng': const CountryInfo(code: 'ng', iso3: 'NGA', name: 'Nigeria', lat: 9.08, lon: 8.68, region: 'Africa'),
  'rw': const CountryInfo(code: 'rw', iso3: 'RWA', name: 'Rwanda', lat: -1.94, lon: 29.87, region: 'Africa'),
  'st': const CountryInfo(code: 'st', iso3: 'STP', name: 'Sao Tome and Principe', lat: 0.19, lon: 6.61, region: 'Africa'),
  'sn': const CountryInfo(code: 'sn', iso3: 'SEN', name: 'Senegal', lat: 14.50, lon: -14.45, region: 'Africa'),
  'sc': const CountryInfo(code: 'sc', iso3: 'SYC', name: 'Seychelles', lat: -4.68, lon: 55.49, region: 'Africa'),
  'sl': const CountryInfo(code: 'sl', iso3: 'SLE', name: 'Sierra Leone', lat: 8.46, lon: -11.78, region: 'Africa'),
  'so': const CountryInfo(code: 'so', iso3: 'SOM', name: 'Somalia', lat: 5.15, lon: 46.20, region: 'Africa'),
  'za': const CountryInfo(code: 'za', iso3: 'ZAF', name: 'South Africa', lat: -30.56, lon: 22.94, region: 'Africa'),
  'ss': const CountryInfo(code: 'ss', iso3: 'SSD', name: 'South Sudan', lat: 6.88, lon: 31.31, region: 'Africa'),
  'sd': const CountryInfo(code: 'sd', iso3: 'SDN', name: 'Sudan', lat: 12.86, lon: 30.22, region: 'Africa'),
  'tz': const CountryInfo(code: 'tz', iso3: 'TZA', name: 'Tanzania', lat: -6.37, lon: 34.89, region: 'Africa'),
  'tg': const CountryInfo(code: 'tg', iso3: 'TGO', name: 'Togo', lat: 8.62, lon: 0.82, region: 'Africa'),
  'tn': const CountryInfo(code: 'tn', iso3: 'TUN', name: 'Tunisia', lat: 33.89, lon: 9.54, region: 'Africa'),
  'ug': const CountryInfo(code: 'ug', iso3: 'UGA', name: 'Uganda', lat: 1.37, lon: 32.29, region: 'Africa'),
  'zm': const CountryInfo(code: 'zm', iso3: 'ZMB', name: 'Zambia', lat: -13.13, lon: 27.85, region: 'Africa'),
  'zw': const CountryInfo(code: 'zw', iso3: 'ZWE', name: 'Zimbabwe', lat: -19.02, lon: 29.15, region: 'Africa'),

  // ── AMERICAS ────────────────────────────────────────────
  'ar': const CountryInfo(code: 'ar', iso3: 'ARG', name: 'Argentina', lat: -38.42, lon: -63.62, region: 'Americas'),
  'bs': const CountryInfo(code: 'bs', iso3: 'BHS', name: 'Bahamas', lat: 25.03, lon: -77.40, region: 'Americas'),
  'bb': const CountryInfo(code: 'bb', iso3: 'BRB', name: 'Barbados', lat: 13.19, lon: -59.54, region: 'Americas'),
  'bz': const CountryInfo(code: 'bz', iso3: 'BLZ', name: 'Belize', lat: 17.19, lon: -88.50, region: 'Americas'),
  'bo': const CountryInfo(code: 'bo', iso3: 'BOL', name: 'Bolivia', lat: -16.29, lon: -63.59, region: 'Americas'),
  'br': const CountryInfo(code: 'br', iso3: 'BRA', name: 'Brazil', lat: -14.24, lon: -51.93, region: 'Americas'),
  'ca': const CountryInfo(code: 'ca', iso3: 'CAN', name: 'Canada', lat: 56.13, lon: -106.35, region: 'Americas'),
  'cl': const CountryInfo(code: 'cl', iso3: 'CHL', name: 'Chile', lat: -35.68, lon: -71.54, region: 'Americas'),
  'co': const CountryInfo(code: 'co', iso3: 'COL', name: 'Colombia', lat: 4.57, lon: -74.30, region: 'Americas'),
  'cr': const CountryInfo(code: 'cr', iso3: 'CRI', name: 'Costa Rica', lat: 9.75, lon: -83.75, region: 'Americas'),
  'cu': const CountryInfo(code: 'cu', iso3: 'CUB', name: 'Cuba', lat: 21.52, lon: -77.78, region: 'Americas'),
  'dm': const CountryInfo(code: 'dm', iso3: 'DMA', name: 'Dominica', lat: 15.41, lon: -61.37, region: 'Americas'),
  'do': const CountryInfo(code: 'do', iso3: 'DOM', name: 'Dominican Republic', lat: 18.74, lon: -70.16, region: 'Americas'),
  'ec': const CountryInfo(code: 'ec', iso3: 'ECU', name: 'Ecuador', lat: -1.83, lon: -78.18, region: 'Americas'),
  'sv': const CountryInfo(code: 'sv', iso3: 'SLV', name: 'El Salvador', lat: 13.79, lon: -88.90, region: 'Americas'),
  'gd': const CountryInfo(code: 'gd', iso3: 'GRD', name: 'Grenada', lat: 12.26, lon: -61.60, region: 'Americas'),
  'gt': const CountryInfo(code: 'gt', iso3: 'GTM', name: 'Guatemala', lat: 15.78, lon: -90.23, region: 'Americas'),
  'gy': const CountryInfo(code: 'gy', iso3: 'GUY', name: 'Guyana', lat: 4.86, lon: -58.93, region: 'Americas'),
  'ht': const CountryInfo(code: 'ht', iso3: 'HTI', name: 'Haiti', lat: 18.97, lon: -72.29, region: 'Americas'),
  'hn': const CountryInfo(code: 'hn', iso3: 'HND', name: 'Honduras', lat: 15.20, lon: -86.24, region: 'Americas'),
  'jm': const CountryInfo(code: 'jm', iso3: 'JAM', name: 'Jamaica', lat: 18.11, lon: -77.30, region: 'Americas'),
  'mx': const CountryInfo(code: 'mx', iso3: 'MEX', name: 'Mexico', lat: 23.63, lon: -102.55, region: 'Americas'),
  'ni': const CountryInfo(code: 'ni', iso3: 'NIC', name: 'Nicaragua', lat: 12.87, lon: -85.21, region: 'Americas'),
  'pa': const CountryInfo(code: 'pa', iso3: 'PAN', name: 'Panama', lat: 8.54, lon: -80.78, region: 'Americas'),
  'py': const CountryInfo(code: 'py', iso3: 'PRY', name: 'Paraguay', lat: -23.44, lon: -58.44, region: 'Americas'),
  'pe': const CountryInfo(code: 'pe', iso3: 'PER', name: 'Peru', lat: -9.19, lon: -75.02, region: 'Americas'),
  'kn': const CountryInfo(code: 'kn', iso3: 'KNA', name: 'Saint Kitts and Nevis', lat: 17.36, lon: -62.78, region: 'Americas'),
  'lc': const CountryInfo(code: 'lc', iso3: 'LCA', name: 'Saint Lucia', lat: 13.91, lon: -60.98, region: 'Americas'),
  'vc': const CountryInfo(code: 'vc', iso3: 'VCT', name: 'Saint Vincent', lat: 12.98, lon: -61.29, region: 'Americas'),
  'sr': const CountryInfo(code: 'sr', iso3: 'SUR', name: 'Suriname', lat: 3.92, lon: -56.03, region: 'Americas'),
  'tt': const CountryInfo(code: 'tt', iso3: 'TTO', name: 'Trinidad and Tobago', lat: 10.69, lon: -61.22, region: 'Americas'),
  'us': const CountryInfo(code: 'us', iso3: 'USA', name: 'United States', lat: 37.09, lon: -95.71, region: 'Americas'),
  'uy': const CountryInfo(code: 'uy', iso3: 'URY', name: 'Uruguay', lat: -32.52, lon: -55.77, region: 'Americas'),
  've': const CountryInfo(code: 've', iso3: 'VEN', name: 'Venezuela', lat: 6.42, lon: -66.59, region: 'Americas'),

  // ── ASIA ────────────────────────────────────────────────
  'af': const CountryInfo(code: 'af', iso3: 'AFG', name: 'Afghanistan', lat: 33.94, lon: 67.71, region: 'Asia'),
  'am': const CountryInfo(code: 'am', iso3: 'ARM', name: 'Armenia', lat: 40.07, lon: 45.04, region: 'Asia'),
  'az': const CountryInfo(code: 'az', iso3: 'AZE', name: 'Azerbaijan', lat: 40.14, lon: 47.58, region: 'Asia'),
  'bh': const CountryInfo(code: 'bh', iso3: 'BHR', name: 'Bahrain', lat: 26.07, lon: 50.56, region: 'Asia'),
  'bd': const CountryInfo(code: 'bd', iso3: 'BGD', name: 'Bangladesh', lat: 23.68, lon: 90.36, region: 'Asia'),
  'bt': const CountryInfo(code: 'bt', iso3: 'BTN', name: 'Bhutan', lat: 27.51, lon: 90.43, region: 'Asia'),
  'bn': const CountryInfo(code: 'bn', iso3: 'BRN', name: 'Brunei', lat: 4.54, lon: 114.73, region: 'Asia'),
  'kh': const CountryInfo(code: 'kh', iso3: 'KHM', name: 'Cambodia', lat: 12.57, lon: 104.99, region: 'Asia'),
  'cn': const CountryInfo(code: 'cn', iso3: 'CHN', name: 'China', lat: 35.86, lon: 104.20, region: 'Asia'),
  'ge': const CountryInfo(code: 'ge', iso3: 'GEO', name: 'Georgia', lat: 42.32, lon: 43.36, region: 'Asia'),
  'in': const CountryInfo(code: 'in', iso3: 'IND', name: 'India', lat: 20.59, lon: 78.96, region: 'Asia'),
  'id': const CountryInfo(code: 'id', iso3: 'IDN', name: 'Indonesia', lat: -0.79, lon: 113.92, region: 'Asia'),
  'ir': const CountryInfo(code: 'ir', iso3: 'IRN', name: 'Iran', lat: 32.43, lon: 53.69, region: 'Asia'),
  'iq': const CountryInfo(code: 'iq', iso3: 'IRQ', name: 'Iraq', lat: 33.22, lon: 43.68, region: 'Asia'),
  'il': const CountryInfo(code: 'il', iso3: 'ISR', name: 'Israel', lat: 31.05, lon: 34.85, region: 'Asia'),
  'jp': const CountryInfo(code: 'jp', iso3: 'JPN', name: 'Japan', lat: 36.20, lon: 138.25, region: 'Asia'),
  'jo': const CountryInfo(code: 'jo', iso3: 'JOR', name: 'Jordan', lat: 30.59, lon: 36.24, region: 'Asia'),
  'kz': const CountryInfo(code: 'kz', iso3: 'KAZ', name: 'Kazakhstan', lat: 48.02, lon: 66.92, region: 'Asia'),
  'kw': const CountryInfo(code: 'kw', iso3: 'KWT', name: 'Kuwait', lat: 29.31, lon: 47.48, region: 'Asia'),
  'kg': const CountryInfo(code: 'kg', iso3: 'KGZ', name: 'Kyrgyzstan', lat: 41.20, lon: 74.77, region: 'Asia'),
  'la': const CountryInfo(code: 'la', iso3: 'LAO', name: 'Laos', lat: 19.86, lon: 102.50, region: 'Asia'),
  'lb': const CountryInfo(code: 'lb', iso3: 'LBN', name: 'Lebanon', lat: 33.85, lon: 35.86, region: 'Asia'),
  'my': const CountryInfo(code: 'my', iso3: 'MYS', name: 'Malaysia', lat: 4.21, lon: 101.98, region: 'Asia'),
  'mv': const CountryInfo(code: 'mv', iso3: 'MDV', name: 'Maldives', lat: 3.20, lon: 73.22, region: 'Asia'),
  'mn': const CountryInfo(code: 'mn', iso3: 'MNG', name: 'Mongolia', lat: 46.86, lon: 103.85, region: 'Asia'),
  'mm': const CountryInfo(code: 'mm', iso3: 'MMR', name: 'Myanmar', lat: 21.91, lon: 95.96, region: 'Asia'),
  'np': const CountryInfo(code: 'np', iso3: 'NPL', name: 'Nepal', lat: 28.39, lon: 84.12, region: 'Asia'),
  'om': const CountryInfo(code: 'om', iso3: 'OMN', name: 'Oman', lat: 21.47, lon: 55.98, region: 'Asia'),
  'pk': const CountryInfo(code: 'pk', iso3: 'PAK', name: 'Pakistan', lat: 30.38, lon: 69.35, region: 'Asia'),
  'ph': const CountryInfo(code: 'ph', iso3: 'PHL', name: 'Philippines', lat: 12.88, lon: 121.77, region: 'Asia'),
  'qa': const CountryInfo(code: 'qa', iso3: 'QAT', name: 'Qatar', lat: 25.35, lon: 51.18, region: 'Asia'),
  'kr': const CountryInfo(code: 'kr', iso3: 'KOR', name: 'South Korea', lat: 35.91, lon: 127.77, region: 'Asia'),
  'sa': const CountryInfo(code: 'sa', iso3: 'SAU', name: 'Saudi Arabia', lat: 23.89, lon: 45.08, region: 'Asia'),
  'sg': const CountryInfo(code: 'sg', iso3: 'SGP', name: 'Singapore', lat: 1.35, lon: 103.82, region: 'Asia'),
  'lk': const CountryInfo(code: 'lk', iso3: 'LKA', name: 'Sri Lanka', lat: 7.87, lon: 80.77, region: 'Asia'),
  'sy': const CountryInfo(code: 'sy', iso3: 'SYR', name: 'Syria', lat: 34.80, lon: 39.00, region: 'Asia'),
  'tw': const CountryInfo(code: 'tw', iso3: 'TWN', name: 'Taiwan', lat: 23.70, lon: 120.96, region: 'Asia'),
  'tj': const CountryInfo(code: 'tj', iso3: 'TJK', name: 'Tajikistan', lat: 38.86, lon: 71.28, region: 'Asia'),
  'th': const CountryInfo(code: 'th', iso3: 'THA', name: 'Thailand', lat: 15.87, lon: 100.99, region: 'Asia'),
  'tl': const CountryInfo(code: 'tl', iso3: 'TLS', name: 'Timor-Leste', lat: -8.87, lon: 125.73, region: 'Asia'),
  'tr': const CountryInfo(code: 'tr', iso3: 'TUR', name: 'Turkey', lat: 38.96, lon: 35.24, region: 'Asia'),
  'tm': const CountryInfo(code: 'tm', iso3: 'TKM', name: 'Turkmenistan', lat: 38.97, lon: 59.56, region: 'Asia'),
  'ae': const CountryInfo(code: 'ae', iso3: 'ARE', name: 'United Arab Emirates', lat: 23.42, lon: 53.85, region: 'Asia'),
  'uz': const CountryInfo(code: 'uz', iso3: 'UZB', name: 'Uzbekistan', lat: 41.38, lon: 64.59, region: 'Asia'),
  'vn': const CountryInfo(code: 'vn', iso3: 'VNM', name: 'Vietnam', lat: 14.06, lon: 108.28, region: 'Asia'),
  'ye': const CountryInfo(code: 'ye', iso3: 'YEM', name: 'Yemen', lat: 15.55, lon: 48.52, region: 'Asia'),

  // ── EUROPE ──────────────────────────────────────────────
  'al': const CountryInfo(code: 'al', iso3: 'ALB', name: 'Albania', lat: 41.15, lon: 20.17, region: 'Europe'),
  'ad': const CountryInfo(code: 'ad', iso3: 'AND', name: 'Andorra', lat: 42.55, lon: 1.60, region: 'Europe'),
  'at': const CountryInfo(code: 'at', iso3: 'AUT', name: 'Austria', lat: 47.52, lon: 14.55, region: 'Europe'),
  'by': const CountryInfo(code: 'by', iso3: 'BLR', name: 'Belarus', lat: 53.71, lon: 27.95, region: 'Europe'),
  'be': const CountryInfo(code: 'be', iso3: 'BEL', name: 'Belgium', lat: 50.50, lon: 4.47, region: 'Europe'),
  'ba': const CountryInfo(code: 'ba', iso3: 'BIH', name: 'Bosnia and Herzegovina', lat: 43.92, lon: 17.68, region: 'Europe'),
  'bg': const CountryInfo(code: 'bg', iso3: 'BGR', name: 'Bulgaria', lat: 42.73, lon: 25.49, region: 'Europe'),
  'hr': const CountryInfo(code: 'hr', iso3: 'HRV', name: 'Croatia', lat: 45.10, lon: 15.20, region: 'Europe'),
  'cy': const CountryInfo(code: 'cy', iso3: 'CYP', name: 'Cyprus', lat: 35.13, lon: 33.43, region: 'Europe'),
  'cz': const CountryInfo(code: 'cz', iso3: 'CZE', name: 'Czech Republic', lat: 49.82, lon: 15.47, region: 'Europe'),
  'dk': const CountryInfo(code: 'dk', iso3: 'DNK', name: 'Denmark', lat: 56.26, lon: 9.50, region: 'Europe'),
  'ee': const CountryInfo(code: 'ee', iso3: 'EST', name: 'Estonia', lat: 58.60, lon: 25.01, region: 'Europe'),
  'fi': const CountryInfo(code: 'fi', iso3: 'FIN', name: 'Finland', lat: 61.92, lon: 25.75, region: 'Europe'),
  'fr': const CountryInfo(code: 'fr', iso3: 'FRA', name: 'France', lat: 46.23, lon: 2.21, region: 'Europe'),
  'de': const CountryInfo(code: 'de', iso3: 'DEU', name: 'Germany', lat: 51.17, lon: 10.45, region: 'Europe'),
  'gr': const CountryInfo(code: 'gr', iso3: 'GRC', name: 'Greece', lat: 39.07, lon: 21.82, region: 'Europe'),
  'hu': const CountryInfo(code: 'hu', iso3: 'HUN', name: 'Hungary', lat: 47.16, lon: 19.50, region: 'Europe'),
  'is': const CountryInfo(code: 'is', iso3: 'ISL', name: 'Iceland', lat: 64.96, lon: -19.02, region: 'Europe'),
  'ie': const CountryInfo(code: 'ie', iso3: 'IRL', name: 'Ireland', lat: 53.14, lon: -7.69, region: 'Europe'),
  'it': const CountryInfo(code: 'it', iso3: 'ITA', name: 'Italy', lat: 41.87, lon: 12.57, region: 'Europe'),
  'xk': const CountryInfo(code: 'xk', iso3: 'XKX', name: 'Kosovo', lat: 42.60, lon: 20.90, region: 'Europe'),
  'lv': const CountryInfo(code: 'lv', iso3: 'LVA', name: 'Latvia', lat: 56.88, lon: 24.60, region: 'Europe'),
  'li': const CountryInfo(code: 'li', iso3: 'LIE', name: 'Liechtenstein', lat: 47.17, lon: 9.56, region: 'Europe'),
  'lt': const CountryInfo(code: 'lt', iso3: 'LTU', name: 'Lithuania', lat: 55.17, lon: 23.88, region: 'Europe'),
  'lu': const CountryInfo(code: 'lu', iso3: 'LUX', name: 'Luxembourg', lat: 49.82, lon: 6.13, region: 'Europe'),
  'mt': const CountryInfo(code: 'mt', iso3: 'MLT', name: 'Malta', lat: 35.94, lon: 14.38, region: 'Europe'),
  'md': const CountryInfo(code: 'md', iso3: 'MDA', name: 'Moldova', lat: 47.41, lon: 28.37, region: 'Europe'),
  'mc': const CountryInfo(code: 'mc', iso3: 'MCO', name: 'Monaco', lat: 43.75, lon: 7.41, region: 'Europe'),
  'me': const CountryInfo(code: 'me', iso3: 'MNE', name: 'Montenegro', lat: 42.71, lon: 19.37, region: 'Europe'),
  'nl': const CountryInfo(code: 'nl', iso3: 'NLD', name: 'Netherlands', lat: 52.13, lon: 5.29, region: 'Europe'),
  'mk': const CountryInfo(code: 'mk', iso3: 'MKD', name: 'North Macedonia', lat: 41.51, lon: 21.75, region: 'Europe'),
  'no': const CountryInfo(code: 'no', iso3: 'NOR', name: 'Norway', lat: 60.47, lon: 8.47, region: 'Europe'),
  'pl': const CountryInfo(code: 'pl', iso3: 'POL', name: 'Poland', lat: 51.92, lon: 19.15, region: 'Europe'),
  'pt': const CountryInfo(code: 'pt', iso3: 'PRT', name: 'Portugal', lat: 39.40, lon: -8.22, region: 'Europe'),
  'ro': const CountryInfo(code: 'ro', iso3: 'ROU', name: 'Romania', lat: 45.94, lon: 24.97, region: 'Europe'),
  'ru': const CountryInfo(code: 'ru', iso3: 'RUS', name: 'Russia', lat: 61.52, lon: 105.32, region: 'Europe'),
  'sm': const CountryInfo(code: 'sm', iso3: 'SMR', name: 'San Marino', lat: 43.94, lon: 12.46, region: 'Europe'),
  'rs': const CountryInfo(code: 'rs', iso3: 'SRB', name: 'Serbia', lat: 44.02, lon: 21.01, region: 'Europe'),
  'sk': const CountryInfo(code: 'sk', iso3: 'SVK', name: 'Slovakia', lat: 48.67, lon: 19.70, region: 'Europe'),
  'si': const CountryInfo(code: 'si', iso3: 'SVN', name: 'Slovenia', lat: 46.15, lon: 14.99, region: 'Europe'),
  'es': const CountryInfo(code: 'es', iso3: 'ESP', name: 'Spain', lat: 40.46, lon: -3.75, region: 'Europe'),
  'se': const CountryInfo(code: 'se', iso3: 'SWE', name: 'Sweden', lat: 60.13, lon: 18.64, region: 'Europe'),
  'ch': const CountryInfo(code: 'ch', iso3: 'CHE', name: 'Switzerland', lat: 46.82, lon: 8.23, region: 'Europe'),
  'ua': const CountryInfo(code: 'ua', iso3: 'UKR', name: 'Ukraine', lat: 48.38, lon: 31.17, region: 'Europe'),
  'gb': const CountryInfo(code: 'gb', iso3: 'GBR', name: 'United Kingdom', lat: 55.38, lon: -3.44, region: 'Europe'),

  // ── OCEANIA ─────────────────────────────────────────────
  'au': const CountryInfo(code: 'au', iso3: 'AUS', name: 'Australia', lat: -25.27, lon: 133.78, region: 'Oceania'),
  'fj': const CountryInfo(code: 'fj', iso3: 'FJI', name: 'Fiji', lat: -17.71, lon: 178.07, region: 'Oceania'),
  'ki': const CountryInfo(code: 'ki', iso3: 'KIR', name: 'Kiribati', lat: -3.37, lon: -168.73, region: 'Oceania'),
  'mh': const CountryInfo(code: 'mh', iso3: 'MHL', name: 'Marshall Islands', lat: 7.13, lon: 171.18, region: 'Oceania'),
  'fm': const CountryInfo(code: 'fm', iso3: 'FSM', name: 'Micronesia', lat: 7.43, lon: 150.55, region: 'Oceania'),
  'nr': const CountryInfo(code: 'nr', iso3: 'NRU', name: 'Nauru', lat: -0.52, lon: 166.93, region: 'Oceania'),
  'nz': const CountryInfo(code: 'nz', iso3: 'NZL', name: 'New Zealand', lat: -40.90, lon: 174.89, region: 'Oceania'),
  'pw': const CountryInfo(code: 'pw', iso3: 'PLW', name: 'Palau', lat: 7.51, lon: 134.58, region: 'Oceania'),
  'pg': const CountryInfo(code: 'pg', iso3: 'PNG', name: 'Papua New Guinea', lat: -6.31, lon: 143.96, region: 'Oceania'),
  'ws': const CountryInfo(code: 'ws', iso3: 'WSM', name: 'Samoa', lat: -13.76, lon: -172.10, region: 'Oceania'),
  'sb': const CountryInfo(code: 'sb', iso3: 'SLB', name: 'Solomon Islands', lat: -9.65, lon: 160.16, region: 'Oceania'),
  'to': const CountryInfo(code: 'to', iso3: 'TON', name: 'Tonga', lat: -21.18, lon: -175.20, region: 'Oceania'),
  'tv': const CountryInfo(code: 'tv', iso3: 'TUV', name: 'Tuvalu', lat: -7.11, lon: 177.65, region: 'Oceania'),
  'vu': const CountryInfo(code: 'vu', iso3: 'VUT', name: 'Vanuatu', lat: -15.38, lon: 166.96, region: 'Oceania'),
};

/// Sorted list of all country names for search/autocomplete.
List<CountryInfo> get sortedCountries {
  final list = allCountries.values.toList();
  list.sort((a, b) => a.name.compareTo(b.name));
  return list;
}

/// Look up a country by ISO-2 code (case insensitive).
CountryInfo? countryByCode(String code) => allCountries[code.toLowerCase()];

/// Look up a country by ISO-3 code (case insensitive).
CountryInfo? countryByIso3(String iso3) {
  final upper = iso3.toUpperCase();
  return allCountries.values.cast<CountryInfo?>().firstWhere(
    (c) => c!.iso3 == upper,
    orElse: () => null,
  );
}

/// Search countries by name (case insensitive, partial match).
List<CountryInfo> searchCountries(String query) {
  if (query.isEmpty) return sortedCountries;
  final q = query.toLowerCase();
  return sortedCountries.where((c) => c.name.toLowerCase().contains(q)).toList();
}
