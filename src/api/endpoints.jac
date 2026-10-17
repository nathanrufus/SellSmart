import os;
import from http { HTTPMethod }
import from src.agents.orchestrator { run_advice }
import from src.agents.brain { llm_enabled }
import from src.api.service { health, list_products, list_counties, list_markets, price_history, quotes, weather, quality, quarantine_rows, search_products, ingest, backtest, trace_for, recent_requests, reload_data }

# REST surface. Every walker is public (no login) for the hackathon demo.
# Responses are wrapped by Jac in {"ok", "data": {"reports": [<payload>]}}.
# Swagger lives at /docs once the server is running.

@restspec(method=HTTPMethod.POST, path="/api/ask")
walker:pub ask {
    has question: str,
        county: str = "",
        product: str = "",
        quantity_bags: float = 0.0,
        language: str = "",
        as_of: str = "";

    can run with Root entry {
        use_llm = llm_enabled();
        report run_advice(self.question, self.county, self.product, self.quantity_bags, self.language, use_llm, self.as_of);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/health")
walker:pub api_health {
    can run with Root entry {
        report health();
    }
}

@restspec(method=HTTPMethod.GET, path="/api/products")
walker:pub api_products {
    can run with Root entry {
        report list_products();
    }
}

@restspec(method=HTTPMethod.GET, path="/api/products/search")
walker:pub api_product_search {
    has q: str,
        limit: int = 10;

    can run with Root entry {
        report search_products(self.q, self.limit);
    }
}

@restspec(method=HTTPMethod.POST, path="/api/ingest")
walker:pub api_ingest {
    has product: str;

    can run with Root entry {
        report ingest(self.product);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/counties")
walker:pub api_counties {
    can run with Root entry {
        report list_counties();
    }
}

@restspec(method=HTTPMethod.GET, path="/api/markets")
walker:pub api_markets {
    has product: str,
        county: str = "",
        window_days: int = 30;

    can run with Root entry {
        report list_markets(self.product, self.county, self.window_days);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/history")
walker:pub api_history {
    has product: str,
        market: str = "",
        days: int = 90;

    can run with Root entry {
        report price_history(self.product, self.market, self.days);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/quotes")
walker:pub api_quotes {
    has product: str,
        county: str = "",
        bags: float = 1.0,
        window_days: int = 30;

    can run with Root entry {
        report quotes(self.product, self.county, self.bags, self.window_days);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/weather")
walker:pub api_weather {
    has county: str;

    can run with Root entry {
        report weather(self.county);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/quality")
walker:pub api_quality {
    can run with Root entry {
        report quality();
    }
}

@restspec(method=HTTPMethod.GET, path="/api/quarantine")
walker:pub api_quarantine {
    has limit: int = 50,
        reason: str = "";

    can run with Root entry {
        report quarantine_rows(self.limit, self.reason);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/backtest")
walker:pub api_backtest {
    has product: str,
        county: str = "",
        weeks: int = 26;

    can run with Root entry {
        report backtest(self.product, self.county, self.weeks);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/trace/{request_id}")
walker:pub api_trace {
    has request_id: str;

    can run with Root entry {
        report trace_for(self.request_id);
    }
}

@restspec(method=HTTPMethod.GET, path="/api/requests")
walker:pub api_requests {
    has limit: int = 10;

    can run with Root entry {
        report recent_requests(self.limit);
    }
}

@restspec(method=HTTPMethod.POST, path="/api/reload")
walker:pub api_reload {
    can run with Root entry {
        report reload_data();
    }
}
