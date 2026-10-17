"""marketwise - Entry Point.

Combines server-side endpoints with the client-side UI.
"""

import from endpoints { Message, PostMessage, ListMessages }

# Soko backend: importing the walkers registers the REST API.
import from src.api.endpoints {
    ask, api_health, api_products, api_product_search, api_ingest, api_counties, api_markets,
    api_history, api_quotes, api_weather, api_quality, api_quarantine, api_backtest,
    api_trace, api_requests, api_reload
}

# Client-side UI

import from .frontend { app as ClientApp }

def:pub app -> JsxElement {
    <ClientApp/>
}
