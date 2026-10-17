import json;
import time;
import from urllib.parse { urlencode }
import from datetime { datetime, timezone }
import from src.ingest.kamis_fetch { download }
import from src.services.models { ForecastDay }
import from src.services.config { load_county_cfgs, path_in, write_json }
import from src.services.util { norm_key, parse_number }

# Seven day rain forecasts per county from Open-Meteo (free, no key). If you
# use another weather source, only forecast_url and parse_forecast change: the
# rest of the app reads data/clean/weather.json.

def forecast_url(lat: float, lon: float) -> str {
    q = urlencode({
        "latitude": lat, "longitude": lon,
        "daily": "precipitation_sum,precipitation_probability_max",
        "forecast_days": 7, "timezone": "Africa/Nairobi"
    });
    return "https://api.open-meteo.com/v1/forecast?" + q;
}

def parse_forecast(text: str) -> list[ForecastDay] {
    out: list[ForecastDay] = [];
    try {
        data = json.loads(text);
    } except ValueError {
        return out;
    }
    if not isinstance(data, dict) {
        return out;
    }
    daily = data.get("daily", {});
    if not isinstance(daily, dict) {
        return out;
    }
    times: list[any] = list(daily.get("time", []));
    mm: list[any] = list(daily.get("precipitation_sum", []));
    pr: list[any] = list(daily.get("precipitation_probability_max", []));
    for i in range(len(times)) {
        mmv = parse_number(mm[i]) if i < len(mm) else None;
        prv = parse_number(pr[i]) if i < len(pr) else None;
        out.append(ForecastDay(day=str(times[i]), rain_mm=float(mmv or 0.0), rain_prob=float(prv or 0.0)));
    }
    return out;
}

def fetch_all(pause_s: float = 0.5) -> dict[str, any] {
    cleaned: dict[str, list[dict[str, any]]] = {};
    failed: list[str] = [];
    for c in load_county_cfgs() {
        key = norm_key(c.name).replace(" ", "_");
        dest = path_in(f"data/raw/weather/{key}.json");
        if not download(forecast_url(c.lat, c.lon), dest, 30) {
            failed.append(c.name);
            continue;
        }
        with open(dest, "r", encoding="utf-8") as fh {
            days = parse_forecast(fh.read());
        }
        if len(days) == 0 {
            failed.append(c.name);
            continue;
        }
        cleaned[c.name] = [{"day": d.day, "rain_mm": d.rain_mm, "rain_prob": d.rain_prob} for d in days];
        time.sleep(pause_s);
    }
    write_json("data/clean/weather.json", {"retrieved_at": datetime.now(timezone.utc).isoformat(), "source": "open-meteo", "counties": cleaned});
    return {"counties_ok": len(cleaned), "counties_failed": failed};
}

with entry:__main__ {
    print(fetch_all());
}
