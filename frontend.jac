"""marketwise (Soko) - Client-Side UI."""

import "./assets/main.css";

import from .components.Header { Header }
import from .components.AnswerCard { AnswerCard }
import from .components.RankingTable { RankingTable }
import from .components.TracePanel { TracePanel }
import from .components.Sparkline { Sparkline }
import from .components.QualityPanel { QualityPanel }
import from .components.BacktestPanel { BacktestPanel }
import from .components.Ui { Badge, Card, arr, dct, txt }
import from .components.Api { apiGet, apiPost }

import from src.api.endpoints { ask, api_health, api_counties, api_quality, api_backtest, api_history, api_product_search }

def:pub app -> JsxElement {
    has health: any = None,
        counties: list[any] = [],
        quality: any = None,
        question: str = "",
        county: str = "",
        bags: str = "",
        language: str = "",
        productQuery: str = "",
        matches: list[any] = [],
        loading: bool = False,
        error: str = "",
        result: any = None,
        history: any = None,
        backtest: any = None,
        btLoading: bool = False,
        tab: str = "trace",
        examples: list[str] = [
            "Where should I sell 10 bags of dried maize? I am in Nakuru",
            "Nauze wapi magunia 5 ya mahindi? Niko Eldoret",
            "I have 20 bags of green grams in Kitui, should I wait?",
            "Where can I sell my beans?"
        ];

    can with entry {
        loadInitial();
    }

    async def loadInitial -> None;
    async def askSoko(e: FormEvent) -> None;
    async def searchProducts(e: ChangeEvent) -> None;
    async def runBacktest -> None;

    def pickProduct(name: str) {
        question = "Where should I sell my " + name + "?" + (" I am in " + county if county != "" else "");
    }

    def setTab(name: str) {
        tab = name;
    }

    plan = result["plan"] if result else None;
    steps = arr(result["trace"]) if result else [];
    can_backtest = bool(plan) and (txt(dct(plan)["county"]) != "") and (txt(dct(plan)["product"]) != "");

    def tabClass(name: str) -> str {
        return "rounded-lg px-3 py-1.5 text-sm font-medium " + ("bg-emerald-600 text-white" if tab == name else "bg-stone-100 text-stone-700 hover:bg-stone-200");
    }

    return <div className="min-h-screen bg-stone-50 text-stone-900">
        <Header health={health}/>
        <main className="mx-auto grid max-w-6xl gap-6 px-4 py-6 lg:grid-cols-5">
            <div className="space-y-6 lg:col-span-2">
                <Card title="Ask Soko" subtitle="In English or Swahili. Name any crop KAMIS tracks.">
                    <form onSubmit={askSoko} className="space-y-3">
                        <textarea
                            value={question}
                            onChange={lambda (e: ChangeEvent) { question = e.target.value; }}
                            rows={3}
                            placeholder="e.g. I have 10 bags of dried maize, where can I sell?"
                            className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-200"
                        ></textarea>
                        <div className="grid grid-cols-2 gap-3">
                            <label className="text-xs text-stone-500">Your county
                                <select
                                    value={county}
                                    onChange={lambda (e: ChangeEvent) { county = e.target.value; }}
                                    className="mt-1 w-full rounded-lg border border-stone-300 bg-white px-2 py-2 text-sm text-stone-900"
                                >
                                    <option value="">Detect from question</option>
                                    {[<option key={c["name"]} value={c["name"]}>{c["name"]}</option> for c in counties]}
                                </select>
                            </label>
                            <label className="text-xs text-stone-500">Bags
                                <input
                                    type="number"
                                    min="1"
                                    value={bags}
                                    onChange={lambda (e: ChangeEvent) { bags = e.target.value; }}
                                    placeholder="from question"
                                    className="mt-1 w-full rounded-lg border border-stone-300 px-2 py-2 text-sm text-stone-900"
                                />
                            </label>
                        </div>
                        <div className="flex items-center gap-2">
                            <span className="text-xs text-stone-500">Reply in</span>
                            <button type="button" onClick={lambda (e: MouseEvent) { language = ""; }} className={"rounded-full px-3 py-1 text-xs " + ("bg-emerald-600 text-white" if language == "" else "bg-stone-100 text-stone-700")}>Auto</button>
                            <button type="button" onClick={lambda (e: MouseEvent) { language = "en"; }} className={"rounded-full px-3 py-1 text-xs " + ("bg-emerald-600 text-white" if language == "en" else "bg-stone-100 text-stone-700")}>English</button>
                            <button type="button" onClick={lambda (e: MouseEvent) { language = "sw"; }} className={"rounded-full px-3 py-1 text-xs " + ("bg-emerald-600 text-white" if language == "sw" else "bg-stone-100 text-stone-700")}>Kiswahili</button>
                        </div>
                        <button
                            type="submit"
                            disabled={loading}
                            className="w-full rounded-lg bg-emerald-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                        >
                            {"The agents are working..." if loading else "Ask Soko"}
                        </button>
                    </form>
                    <div className="mt-4 flex flex-wrap gap-2">
                        {[
                            <button key={str(i)} type="button" onClick={lambda (e: MouseEvent) { question = ex; }} className="rounded-full border border-stone-200 bg-stone-50 px-3 py-1 text-left text-xs text-stone-600 hover:bg-stone-100">{ex}</button>
                            for (i, ex) in enumerate(examples)
                        ]}
                    </div>
                    {error != "" and <p className="mt-3 rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-800">{error}</p>}
                </Card>
                <Card title="Find a product" subtitle="Search every product KAMIS lists, by name.">
                    <input
                        type="text"
                        value={productQuery}
                        onChange={searchProducts}
                        placeholder="e.g. tomatoes, irish potato, beans"
                        className="w-full rounded-lg border border-stone-300 px-3 py-2 text-sm"
                    />
                    <div className="mt-3 flex flex-wrap gap-2">
                        {[
                            <button key={m["name"]} type="button" onClick={lambda (e: MouseEvent) { pickProduct(txt(m["name"])); }} className="flex items-center gap-1 rounded-full border border-stone-200 px-3 py-1 text-xs hover:bg-stone-50">
                                {m["name"]}
                                <Badge text={"ready" if m["loaded"] else "fetches on ask"} tone={"green" if m["loaded"] else "blue"}/>
                            </button>
                            for m in matches
                        ]}
                    </div>
                </Card>
            </div>
            <div className="space-y-6 lg:col-span-3">
                {loading and <div className="animate-pulse rounded-2xl border border-emerald-200 bg-white p-6 text-sm text-stone-500">
                    Planner, price analyst, weather analyst, critic and advisor are working on your question...
                </div>}
                {result and not loading and <AnswerCard data={result}/>}
                {result and not loading and len(arr(result["ranking"])) > 0 and <RankingTable rows={arr(result["ranking"])} excluded={arr(result["excluded_markets"])}/>}
                {not result and not loading and <div className="rounded-2xl border border-dashed border-stone-300 bg-white p-8 text-center text-stone-500">
                    Ask a question to see the recommended market, what you keep after transport, and how the agents reached it.
                </div>}
                <Card title="Under the hood" subtitle="Evidence for the advice, and proof it works.">
                    <div className="mb-4 flex flex-wrap gap-2">
                        <button type="button" onClick={lambda (e: MouseEvent) { setTab("trace"); }} className={tabClass("trace")}>Agent trace</button>
                        <button type="button" onClick={lambda (e: MouseEvent) { setTab("trend"); }} className={tabClass("trend")}>Price trend</button>
                        <button type="button" onClick={lambda (e: MouseEvent) { setTab("quality"); }} className={tabClass("quality")}>Data quality</button>
                        <button type="button" onClick={lambda (e: MouseEvent) { setTab("backtest"); }} className={tabClass("backtest")}>Backtest</button>
                    </div>
                    {tab == "trace" and (<TracePanel steps={steps} notes={arr(dct(plan)["notes"])} mode={txt(dct(plan)["planner_mode"])}/> if result else <p className="text-sm text-stone-500">The trace appears after your first question.</p>)}
                    {tab == "trend" and (<Sparkline points={arr(history["points"])}/> if (history and history["ok"]) else <p className="text-sm text-stone-500">Ask a question to see the price history of the recommended market.</p>)}
                    {tab == "quality" and <QualityPanel q={quality}/>}
                    {tab == "backtest" and <BacktestPanel bt={backtest} loading={btLoading} canRun={can_backtest} onRun={runBacktest}/>}
                </Card>
            </div>
        </main>
        <footer className="mx-auto max-w-6xl px-4 pb-8 text-xs text-stone-400">
            Prices from KAMIS. Transport cost is an estimate from county distances. Advice is not a guarantee.
        </footer>
    </div>;
}
