"""Top bar: brand, data freshness and the language switch."""

def lang_class(on: bool) -> str {
    return "min-h-11 px-4 text-sm font-semibold " + ("bg-soko-green text-white" if on else "bg-white text-soko-green");
}

def:pub Header(health: any, language: str, onLang: Callable[[str], None]) -> JsxElement {
    data = health["data"] if health else None;
    synthetic = bool(data["synthetic"]) if data else False;
    return <header className="border-b border-soko-line bg-white">
        {synthetic and <div className="bg-soko-maize px-4 py-2 text-center text-sm text-soko-ink">Demo data: these prices are synthetic and for development only.</div>}
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-x-6 gap-y-3 px-4 py-4 sm:px-8">
            <div className="flex items-baseline gap-3">
                <span className="text-3xl font-extrabold tracking-tight text-soko-deep">Soko</span>
                <span className="hidden text-base text-soko-muted sm:inline">Where to sell, what you keep, and when to wait</span>
            </div>
            <div className="flex items-center gap-4">
                {data and <span className="hidden text-sm text-soko-muted md:inline">{"Prices from KAMIS, latest " + str(data["latest_day"])}</span>}
                <div className="flex overflow-hidden rounded-full border-2 border-soko-green">
                    <button type="button" aria-pressed={language == "en"} onClick={lambda (e: MouseEvent) { onLang("en"); }} className={lang_class(language == "en")}>English</button>
                    <button type="button" aria-pressed={language == "sw"} onClick={lambda (e: MouseEvent) { onLang("sw"); }} className={lang_class(language == "sw")}>Kiswahili</button>
                </div>
            </div>
        </div>
    </header>;
}
