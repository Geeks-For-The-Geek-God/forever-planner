"""Shared test helpers: the files to load come from the TOC, in its order."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "ForeverPlanner")


def toc_files(routes=True):
    """Addon files in TOC order. routes=False leaves out the shared levelling routes, so the
    Druid's own route is the whole plan (the tests written before 0.5 expect that)."""
    out = []
    with open(os.path.join(ADDON, "ForeverPlanner.toc"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            path = line.replace("\\", "/")
            if not routes and path.startswith("Data/Routes/"):
                continue
            out.append(path)
    return out
