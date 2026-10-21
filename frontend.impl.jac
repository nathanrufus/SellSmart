"""Implementations for the Soko frontend component."""

impl app.loadInitial -> None {
    try {
        health = await apiGet("/api/health");
        c = await apiGet("/api/counties");
        counties = arr(c["counties"]);
        quality = await apiGet("/api/quality");
    } except Exception as ex {
        error = "Could not reach the Soko API: " + str(ex);
    }
}

impl app.askSoko(e: FormEvent) -> None {
    e.preventDefault();
    if not question.strip() {
        return;
    }
    loading = True;
    error = "";
    history = None;
    backtest = None;
    try {
        n = float(bags) if bags.strip() else 0.0;
        result = await apiPost("/api/ask", {"question": question, "county": county, "quantity_bags": n, "language": language});
        rec = result["recommendation"];
        if rec {
            history = await apiGet("/api/history?product=" + encodeURIComponent(txt(result["plan"]["product"])) + "&market=" + encodeURIComponent(txt(rec["market"])) + "&days=60");
        }
    } except Exception as ex {
        error = "Something went wrong while asking Soko: " + str(ex);
    }
    loading = False;
}

impl app.searchProducts(e: ChangeEvent) -> None {
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

impl app.runBacktest -> None {
    if not result {
        return;
    }
    btLoading = True;
    try {
        backtest = await apiGet("/api/backtest?product=" + encodeURIComponent(txt(result["plan"]["product"])) + "&county=" + encodeURIComponent(txt(result["plan"]["county"])) + "&weeks=26");
    } except Exception as ex {
        error = "The backtest could not run.";
    }
    btLoading = False;
}