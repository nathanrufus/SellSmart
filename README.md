# Soko

Soko tells a Kenyan farmer where to sell a crop, what they will really keep after transport, and whether to sell now or wait. It runs on live market prices from KAMIS and weather forecasts from Open-Meteo. It answers in English or Kiswahili.

Built in Jac (Jaseci) for JacHacks Kenya, and kept going as a real product.

## What it does

The farmer picks a crop, the number of 90 kg bags and a county, or types a question in their own words ("Nauze wapi magunia 5 ya mahindi? Niko Eldoret"). Soko returns:

- The best market to sell at, and the total the farmer keeps after transport.
- A sell now or wait signal, with plain reasons (price trend, transport cost, rain).
- Every other market ranked by what the farmer keeps per bag, plus the nearest market for comparison.
- The advice written out in words, with a note on whether AI wrote it.
- A "How Soko decided" panel: the five agents, every step, the price trend, data quality, and a check of past advice against selling at the nearest market.

## How it works

A request passes through five agents. Code guards every number, so the model can explain but never invent.

1. Planner: reads the question and extracts product, county, bags and language. Rules run first, `by llm` fills the gaps. Its product and county are checked against the KAMIS catalog and the county list.
2. Price analyst: walks the graph `Product -> Listing -> Market -> County` and computes the net price per market after transport.
3. Weather analyst: assesses rain risk per county from stored forecasts.
4. Critic: rules reject stale, thin and outlier markets. An LLM critic then gives a second opinion, but it can only tighten the result, never rescue a rejected market. A rejection triggers a re-plan with a wider window, up to twice.
5. Advisor: writes the farmer's message from the verified facts. Every number in the text must exist in the facts, otherwise the template answer is used. The response says which one was used (`answer.source`).

If the model is unavailable (no key, no network, rate limit), every agent falls back to its rules and the app still answers. Each step is recorded in the trace.

Transport is an estimate: distance between counties x 1.3 road factor x 2 KES per km per bag, plus 30 KES handling. It is not a quote.

## Requirements

- Jac 0.37.25 (pinned in `jac.toml`)
- Node tooling is installed by Jac for the client (Vite, Tailwind v4)
- A Gemini API key if you want AI wording (free tier works but is rate limited)

## Setup

```
jac install
jac install --pypi litellm
```

Create a `.env` file next to `jac.toml`. Never commit it.

```
SOKO_USE_LLM=1
SOKO_MODEL=gemini/gemini-2.5-flash-lite
GEMINI_API_KEY=your-key-here
```

Set `SOKO_USE_LLM=0` to run on rules only, with no key.

## Load the data

Ingestion scripts must be run with `--no-takeover`. Without it, `jac run` starts the app server instead of the script.

```
jac run --no-takeover src/ingest/kamis_fetch.jac catalog
jac run --no-takeover src/ingest/kamis_fetch.jac
jac run --no-takeover src/ingest/clean.jac
jac run --no-takeover src/ingest/weather_fetch.jac
```

1. `catalog` lists every KAMIS commodity once, so crops can be found by name.
2. The second command downloads the core products.
3. `clean.jac` cleans the data and quarantines bad rows with a reason.
4. `weather_fetch.jac` stores a 7 day forecast per county.

To add any other crop, name it: `jac run --no-takeover src/ingest/kamis_fetch.jac "dry beans" tomatoes`. A crop that is listed by KAMIS but not downloaded yet is fetched on demand when someone asks for it. Set `SOKO_LIVE_FETCH=0` to turn that off.

`config/products.json` has a `per_page` value that controls how many rows are requested per download. A smaller value such as `6000` makes the first fetch faster.

## Run

```
jac run --dev main.jac
```

Open the address Jac prints, usually `http://localhost:8000`. Use Ctrl+Shift+R after changing front-end files.

## Keeping data fresh

- Prices: when a crop's newest price is older than `SOKO_PRICE_MAX_AGE_DAYS` (default 2), Soko re-downloads it before answering, at most once per 6 hours per crop. If KAMIS cannot be reached, it answers from loaded data and says so in the trace.
- Weather: when the forecast is older than `SOKO_WEATHER_MAX_AGE_HOURS` (default 12), a background refresh starts and the request continues with the current forecast.
- Full refresh: `GET /api/refresh` re-downloads every loaded crop and the weather. Call it from cron, for example `0 5 * * * curl -s localhost:8000/api/refresh`.
- `SOKO_AUTO_REFRESH=0` turns this off. `SOKO_LIVE_FETCH=0` turns off all network fetching.

This section applies once `src/ingest/refresh.jac` and the `api_refresh` walker are in your project.

## API

Responses use one envelope: `{"ok", "type", "data": {"result", "reports": [payload]}, "error"}`. The payload is `reports[0]`.

| Method | Path | Purpose |
|---|---|---|
| POST | /api/ask | Question in, advice out (`question`, optional `county`, `product`, `quantity_bags`, `language`) |
| POST | /api/ingest | Download and load a product by name (`product`) |
| GET | /api/health | Data counts, freshness, model status |
| GET | /api/products | Loaded products |
| GET | /api/products/search | Search every KAMIS product by name (`q`, `limit`) |
| GET | /api/counties | Supported counties |
| GET | /api/markets | Markets and latest price for a product |
| GET | /api/history | Daily price series and trend (`product`, `market`, `days`) |
| GET | /api/quotes | Net price ranking without the full agent loop |
| GET | /api/weather | Rain risk for a county |
| GET | /api/quality | Data quality summary |
| GET | /api/quarantine | Dropped rows with reasons |
| GET | /api/backtest | Past advice vs nearest market (`product`, `county`, `weeks`) |
| GET | /api/trace | Agent trace for a request |
| GET | /api/requests | Recent requests |
| GET | /api/reload | Reload data into the graph |
| GET | /api/refresh | Re-download prices and weather, then reload |

## Project layout

```
main.jac            entry point, registers the API
frontend.jac        the client app and its state
assets/main.css     Tailwind v4 theme and colours
components/         Header, AskForm, Verdict, Reasons, MarketList,
                    InWords, Notice, Decided, and the evidence panels
config/             counties, products, thresholds, rates, EN/SW text
src/services/       stats, transport, net price, trend, rules, backtest
src/ingest/         KAMIS fetch, cleaning, weather, refresh
src/graph/          nodes, edges, loader
src/agents/         planner, price and weather analysts, critic, advisor, orchestrator
src/api/            service functions and REST walkers
tests/              test suite
data/               catalog, cleaned prices, weather, quarantine (generated)
```

## Tests

```
jac test -d tests
```

The tests mock the model, so no API key is needed.

## Troubleshooting

- "Could not reach the Soko API": the server is not running, or the data was never loaded. Start it with `jac run --dev main.jac` and check `/api/health`.
- "listed by KAMIS but I could not get its prices": the crop was found but the download failed. Check the connection and try again.
- Answers read like a template: the model hit a rate limit or has no key. Use `gemini-2.5-flash-lite`, wait between questions, or check `GEMINI_API_KEY`.
- No rain information: run `weather_fetch.jac`, then `GET /api/reload`.

## Data and limits

Prices come from KAMIS (Kenya's agricultural market information system) and forecasts from Open-Meteo. Soko shows how many reports each advice rests on and how recent they are. Advice is not a guarantee, and transport costs are estimates.
