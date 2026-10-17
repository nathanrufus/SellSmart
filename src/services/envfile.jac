import os;

# Reads KEY=value lines from <project>/.env into the environment.
# Variables already set in the shell win over the file.
def load_dotenv(path: str = "") {
    full = path if path != "" else os.path.join(os.environ.get("SOKO_HOME", os.getcwd()), ".env");
    if not os.path.exists(full) {
        return;
    }
    with open(full, "r", encoding="utf-8") as fh {
        for raw in fh.read().splitlines() {
            line = raw.strip();
            if line == "" or line.startswith("#") or "=" not in line {
                continue;
            }
            (k, v) = line.split("=", 1);
            k = k.strip();
            if k not in os.environ {
                os.environ[k] = v.strip().strip('"').strip("'");
            }
        }
    }
}