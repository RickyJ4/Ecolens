from geopy.distance import geodesic

def distance_km(point_a, point_b):
    return geodesic(point_a, point_b).km
