"""Implementations for the Soko frontend component."""

impl app.loadInitial -> None {
    try {
        h = root spawn api_health();
        health = h.reports[0];
        c = root spawn api_counties();
        counties = arr(c.reports[0]["counties"]);
        q = root spawn api_quality();
        quality = q.reports[0];
    } except Exception as ex {
        error = "Could not reach the Soko API. Is the server running?";
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
        r = root spawn ask(question=question, county=county, quantity_bags=n, language=language);
        result = r.reports[0];
        rec = result["recommendation"];
        if rec {
            hh = root spawn api_history(product=txt(result["plan"]["product"]), market=txt(rec["market"]), days=60);
            history = hh.reports[0];
        }
    } except Exception as ex {
        error = "Something went wrong while asking Soko. Please try again.";
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
        r = root spawn api_product_search(q=productQuery, limit=8);
        matches = arr(r.reports[0]["matches"]);
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
        r = root spawn api_backtest(product=txt(result["plan"]["product"]), county=txt(result["plan"]["county"]), weeks=26);
        backtest = r.reports[0];
    } except Exception as ex {
        error = "The backtest could not run.";
    }
    btLoading = False;
}
