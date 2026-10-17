import from src.services.util { haversine_km }
import from src.services.config { CountyCfg, Rates }

def road_distance_km(a: CountyCfg, b: CountyCfg, rates: Rates) -> float {
    if a.name == b.name {
        return 0.0;
    }
    return haversine_km(a.lat, a.lon, b.lat, b.lon) * rates.road_factor;
}

def cost_per_bag(distance_km: float, rates: Rates) -> float {
    return distance_km * rates.cost_per_km_per_bag + rates.handling_cost_per_bag;
}

def cost_per_kg(distance_km: float, bag_kg: float, rates: Rates) -> float {
    if bag_kg <= 0.0 {
        return 0.0;
    }
    return cost_per_bag(distance_km, rates) / bag_kg;
}
