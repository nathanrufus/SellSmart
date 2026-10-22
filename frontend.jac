"""marketwise (Soko) - Client-Side UI."""

import "./assets/main.css";

import from .components.Api { apiGet, apiPost }
import from .components.Ui { arr, dct, txt }
import from .components.Header { Header }
import from .components.AskForm { AskForm }
import from .components.Verdict { Verdict }
import from .components.Reasons { Reasons }
import from .components.MarketList { MarketList }
import from .components.InWords { InWords }
import from .components.Notice { Notice }
import from .components.Decided { Decided }

import from src.api.endpoints { ask, api_health, api_counties, api_quality, api_backtest, api_history, api_product_search }

def:pub app -> JsxElement {
    has health: any = None,
        counties: list[any] = [],
        quality: any = None,
        crops: list[str] = ["Dry Maize", "Beans Rosecoco", "Green Grams"],
        crop: str = "",
        bags: str = "10",
        county: str = "",
        question: str = "",
        language: str = "en",
        searchOpen: bool = False,
        productQuery: str = "",
        matches: list[any] = [],
        loading: bool = False,
        error: str = "",
        result: any = None,
        history: any = None,
        backtest: any = None,
        btLoading: bool = False,
        expanded: bool = False;

    can with entry {
        loadInitial();
    }

    async def loadInitial -> None {
        try {
            health = await apiGet("/api/health");
            c = await apiGet("/api/counties");
            counties = arr(c["counties"]);
            quality = await apiGet("/api/quality");
        } except Exception as ex {
            error = "Soko could not reach its data service: " + str(ex);
        }
    }

    async def runAsk(q: str) -> None {
        loading = True;
        error = "";
        history = None;
        backtest = None;
        expanded = False;
        try {
            n = float(bags) if bags.strip() else 0.0;
            payload = {"question": q, "county": county, "product": crop, "quantity_bags": n, "language": language};
            result = await apiPost("/api/ask", payload);
            rec = result["recommendation"];
            if rec {
                history = await apiGet("/api/history?product=" + encodeURIComponent(txt(result["plan"]["product"])) + "&market=" + encodeURIComponent(txt(rec["market"])) + "&days=60");
            }
        } except Exception as ex {
            error = "Something went wrong while asking Soko: " + str(ex);
        }
        loading = False;
    }

    async def submitAsk(e: FormEvent) -> None {
        e.preventDefault();
        typed = question.strip();
        if typed == "" and crop == "" {
            error = "Choose what you are selling, or type your question.";
            return;
        }
        if typed == "" and county == "" {
            error = "Choose your county so Soko can work out transport.";
            return;
        }
        q = typed if typed != "" else "Where should I sell my " + crop + "?";
        await runAsk(q);
    }

    async def pickCandidate(name: str) -> None {
        crop = name;
        question = "";
        await runAsk("Where should I sell my " + name + "?");
    }

    async def searchProducts(e: ChangeEvent) -> None {
        productQuery = e.target.value;
        if len(productQuery.strip()) < 2 {
            matches = [];
            return;
        }
        try {
            r = await apiGet("/api/products/search?q=" + encodeURIComponent(productQuery) + "&limit=8");
            matches = arr(r["matches"]);
        } except Exception as ex {
            matches = [];
        }
    }

    async def runBacktest -> None {
        if not result {
            return;
        }
        btLoading = True;
        try {
            backtest = await apiGet("/api/backtest?product=" + encodeURIComponent(txt(result["plan"]["product"])) + "&county=" + encodeURIComponent(txt(result["plan"]["county"])) + "&weeks=26");
        } except Exception as ex {
            error = "The comparison with past advice could not run: " + str(ex);
        }
        btLoading = False;
    }

    def chooseCrop(name: str) {
        crop = name;
        searchOpen = False;
    }

    def moreBags(step: int) {
        n = int(float(bags)) if bags.strip() else 0;
        n = n + step;
        if n < 1 {
            n = 1;
        }
        bags = str(n);
    }

    plan = result["plan"] if result else None;
    steps = arr(result["trace"]) if result else [];
    has_rec = bool(result) and bool(result["recommendation"]);
    can_backtest = bool(plan) and (txt(dct(plan)["county"]) != "") and (txt(dct(plan)["product"]) != "");

    return <div className="min-h-screen bg-soko-ground text-soko-ink">
        <Header health={health} language={language} onLang={lambda (l: str) { language = l; }}/>
        <main className="mx-auto grid max-w-6xl gap-6 px-4 py-6 sm:px-8 lg:grid-cols-[400px_1fr]">
            <div className="flex min-w-0 flex-col gap-4">
                <AskForm
                    crop={crop} crops={crops} bags={bags} county={county} counties={counties} question={question}
                    loading={loading} searchOpen={searchOpen} productQuery={productQuery} matches={matches}
                    onCrop={chooseCrop}
                    onMinus={lambda { moreBags(-1); }}
                    onPlus={lambda { moreBags(1); }}
                    onBags={lambda (e: ChangeEvent) { bags = e.target.value; }}
                    onCounty={lambda (e: ChangeEvent) { county = e.target.value; }}
                    onQuestion={lambda (e: ChangeEvent) { question = e.target.value; }}
                    onSearch={searchProducts}
                    onToggleSearch={lambda { searchOpen = not searchOpen; }}
                    onSubmit={submitAsk}
                />
                {error != "" and <p role="alert" className="rounded-2xl border-2 border-soko-tomato bg-white px-4 py-3 text-base">{error}</p>}
            </div>
            <div className="flex min-w-0 flex-col gap-6">
                {loading and <div className="animate-pulse rounded-[18px] border border-soko-line bg-white p-7 text-lg text-soko-muted">
                    Soko is reading the latest prices and checking transport...
                </div>}
                {not result and not loading and <div className="rounded-[18px] border-2 border-dashed border-soko-edge bg-white p-8 text-lg text-soko-muted">
                    Choose your crop, how many bags and your county. Soko shows the best market, what you keep after transport, and whether to sell now or wait.
                </div>}
                {result and not loading and has_rec and <Verdict data={result}/>}
                {result and not loading and not has_rec and <Notice data={result} onPick={pickCandidate}/>}
                {result and not loading and has_rec and <div className="grid min-w-0 gap-6 xl:grid-cols-2">
                    <Reasons data={result}/>
                    <MarketList rows={arr(result["ranking"])} nearest={result["nearest_baseline"]} expanded={expanded} onToggle={lambda { expanded = not expanded; }}/>
                </div>}
                {result and not loading and <InWords data={result}/>}
                {result and not loading and <Decided
                    steps={steps} notes={arr(dct(plan)["notes"])} mode={txt(dct(plan)["planner_mode"])} plan={plan}
                    excluded={arr(result["excluded_markets"])} history={history} quality={quality}
                    bt={backtest} btLoading={btLoading} canRun={can_backtest} onRun={runBacktest}
                />}
            </div>
        </main>
        <footer className="mx-auto max-w-6xl px-4 pb-8 text-sm text-soko-muted sm:px-8">
            Prices from KAMIS. Transport is an estimate from county distances. Advice is not a guarantee.
        </footer>
    </div>;
}
