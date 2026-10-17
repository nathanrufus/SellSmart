import from src.services.models { PriceRec, ForecastDay }

# The graph. Product -> Listing (one per market selling that product) ->
# Market -> County, and County -> Weather. Walkers move across these edges.

node Product {
    has name: str;
}

node County {
    has name: str;
}

node Market {
    has name: str;
}

node Listing {
    has product: str,
        market: str,
        county: str,
        recs: list[PriceRec] = [];
}

node Weather {
    has county: str,
        days: list[ForecastDay] = [];
}

node GraphMeta {
    has loaded_at: str = "",
        synthetic: bool = False,
        products: int = 0,
        markets: int = 0,
        listings: int = 0,
        reports: int = 0,
        counties_with_weather: int = 0,
        latest_day: str = "",
        earliest_day: str = "";
}

node AdviceRecord {
    has request_id: str,
        question: str,
        created_at: str,
        payload: dict[str, any] = {};
}

edge Lists: Product --> Listing {}
edge SoldIn: Listing --> Market {}
edge LocatedIn: Market --> County {}
edge Forecast: County --> Weather {}
