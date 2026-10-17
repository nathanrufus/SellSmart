# Soko: Virtual Agro Advisor (backend)

Soko tells a Kenyan farmer where to sell a crop, what they will really take home after transport, and whether to wait. Built in Jac for JacHacks Kenya.

## What makes it agentic

A request runs through five agents. Three of them reason with an LLM through Jac's `by llm` (byLLM); code guards every number.

1. Planner (`by llm`) reads the question in English or Swahili and returns a structured plan: product, county, bags, language, intent. Rules run first; the model fills what they miss. Its product and county are validated against the KAMIS catalog and the county list, so it cannot invent either.
2. Price analyst (walker) traverses `Product -> Listing -> Market -> County` and measures every market, then computes net price after transport.
3. Weather analyst (walker) assesses rain risk per county from stored Open-Meteo forecasts.
4. Critic: rules reject stale, thin and outlier markets. Then the LLM critic (`by llm`) reviews the evidence as a second opinion and may drop a market it does not trust or ask for a wider search. It can only tighten, never rescue a rejected market or name a market that was not ranked. A rejection triggers a re-plan with a wider window, up to 2 times.
5. Advisor (`by llm`) writes the farmer's message in English or Swahili from the verified facts. Every number in its text must exist in the facts, otherwise the template answer is used. The response says which one was used in `answer.source`.

If the model is unavailable (no key, no network), every agent falls back to its rules and the API still answers. Every step, including LLM steps and fallbacks, is in the trace at `/api/trace/{request_id}`.

Configure the model with environment variables:

```
export SOKO_MODEL=claude-sonnet-4-6        # any LiteLLM model name, e.g. gpt-4o or gemini/gemini-2.0-flash
export ANTHROPIC_API_KEY=...               # or OPENAI_API_KEY / GEMINI_API_KEY to match the model
export SOKO_USE_LLM=1                      # default; set 0 to run rules only
```

`/api/health` shows the model, whether it is enabled and which keys are present. Tests mock the model with byLLM's `MockLLM`, so the suite needs no API key.

## Features

- Net price per market: gross price minus estimated transport (haversine x 1.3 road factor x 2 KES/km/bag, plus 30 KES handling).
- Hold or sell signal from a price trend, last year's seasonality, and the rain forecast.
- Backtest: replays the last N weeks and compares following Soko against selling at the nearest market, using only data available at each cutoff.
- Data quality: every dropped row is quarantined with a reason (duplicate, no price, outlier, supply outlier).
- Any KAMIS product, by name, not by id. `catalog` lists every KAMIS commodity once; after that "dried maize", "tomatoes" or "irish potatoes" resolve to the right product. A name shared by several products ("beans") makes Soko ask which one. A product that is listed but not downloaded yet is fetched, cleaned and loaded on demand when someone asks for it (`SOKO_LIVE_FETCH=0` turns this off).

## Run it

```
pip install jaclang byllm openpyxl jac-scale
jac run src/ingest/kamis_fetch.jac catalog      # find product ids by name
jac run src/ingest/kamis_fetch.jac              # download the core products
jac run src/ingest/kamis_fetch.jac "dry beans" tomatoes   # download any products by name
jac run src/ingest/kamis_fetch.jac all          # or every product in the catalog
jac run src/ingest/clean.jac                    # clean and quarantine
jac run src/ingest/weather_fetch.jac            # 7 day forecast per county
jac start main.jac --no_client                  # API on :8000
jac test -d tests                               # 69 tests
```

For development without KAMIS: `jac run src/ingest/demo_data.jac` writes clearly flagged SYNTHETIC data. `/api/health` warns while synthetic data is loaded. Freeze real data before recording the demo.


## Endpoints

| Method | Path | Purpose |
|---|---|---|
| POST | /api/ask | Question in, advice out (`question`, optional `county`, `product`, `quantity_bags`, `language`) |
| GET | /api/health | Data counts, freshness, synthetic flag |
| GET | /api/products, /api/counties | Loaded products and counties |
| GET | /api/markets | Markets and latest price for a product |
| GET | /api/history | Daily price series and trend |
| GET | /api/quotes | Net price ranking without the full agent loop |
| GET | /api/weather | Rain risk for a county |
| GET | /api/quality | Data quality panel |
| GET | /api/quarantine | Dropped rows with reasons |
| GET | /api/backtest | Advice vs nearest market |
| GET | /api/trace/{request_id} | Agent trace and critic decisions |
| GET | /api/requests | Recent requests |
| POST | /api/reload | Reload data into the graph |

## Layout

```
main.jac            entry, registers endpoints
config/             counties, products, thresholds, rates, EN/SW strings
src/services/       pure logic: stats, transport, net price, trend, rules, backtest
src/ingest/         KAMIS fetch, cleaning, weather, demo data
src/graph/          nodes, edges, loader
src/agents/         walkers, planner, critic, advisor, orchestrator
src/api/            service functions and REST walkers
tests/              69 tests
```

Transport costs are estimates from county distances, not quotes. Backtest results depend on the data window and say so in their notes.
