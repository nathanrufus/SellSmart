import from src.graph.nodes { Product, County, Listing, Weather, Lists, Forecast }
import from src.services.models { ListingData, MarketStat, RainRisk }
import from src.services.config { load_thresholds }
import from src.services.stats { compute_market_stat }
import from src.services.trend { assess_rain }

# Analyst walkers. They move across the graph and write what they find onto
# themselves (has fields); the orchestrator reads the results after the spawn.

walker GatherMarkets {
    has product: str,
        as_of: int,
        window_days: int = 30,
        stats: list[MarketStat] = [],
        listings: list[ListingData] = [];

    can start with Root entry {
        visit [-->[?:Product, name == self.product]];
    }

    can fan_out with Product entry {
        visit [here ->:Lists:->[?:Listing]];
    }

    can measure with Listing entry {
        self.listings.append(ListingData(market=here.market, county=here.county, recs=here.recs));
        self.stats.append(compute_market_stat(here.recs, here.product, here.market, here.county, self.as_of, self.window_days));
    }
}

walker WeatherAnalyst {
    has counties: list[str],
        risks: dict[str, RainRisk] = {};

    can start with Root entry {
        visit [-->[?:County]];
    }

    can at_county with County entry {
        if here.name in self.counties {
            visit [here ->:Forecast:->[?:Weather]];
        }
    }

    can at_weather with Weather entry {
        self.risks[here.county] = assess_rain(here.county, here.days, load_thresholds());
    }
}
