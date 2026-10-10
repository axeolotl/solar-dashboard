#!/usr/bin/env python3
"""Compare the image tags pinned in docker-compose.yml with the newest
stable tags on Docker Hub (same tag suffix, e.g. "-ubuntu").

usage: test/check-versions.py
"""
import json, os, re, urllib.request

compose = os.path.join(os.path.dirname(__file__), "..", "docker-compose.yml")
images = sorted(set(re.findall(r"^\s+image:\s*(\S+):(\S+)\s*$", open(compose).read(), re.M)))

def tags(repo):
    if "/" not in repo:
        repo = "library/" + repo
    url = f"https://hub.docker.com/v2/repositories/{repo}/tags?page_size=100&ordering=last_updated"
    names = []
    for _ in range(3):  # newest 300 tags are plenty
        data = json.load(urllib.request.urlopen(url, timeout=30))
        names += [t["name"] for t in data["results"]]
        url = data.get("next")
        if not url:
            break
    return names

def key(v):
    return tuple(int(x) for x in v.split("."))

for repo, tag in images:
    m = re.fullmatch(r"(\d+(?:\.\d+)*)(.*)", tag)
    if not m:
        print(f"{repo}:{tag}  (not a version tag, skipped)")
        continue
    cur, suffix = m.groups()
    depth = cur.count(".")
    cands = [t[: len(t) - len(suffix)] if suffix else t for t in tags(repo)
             if (t.endswith(suffix) if suffix else True)]
    cands = [c for c in cands if re.fullmatch(r"\d+" + r"\.\d+" * depth, c)]  # stable, same precision
    newest = max(cands, key=key, default=cur)
    state = "up to date" if key(newest) <= key(cur) else f"UPDATE AVAILABLE -> {newest}{suffix}"
    major = "" if newest.split(".")[0] == cur.split(".")[0] else "  (major upgrade, see UPDATING.md)"
    print(f"{repo}:{tag}  {state}{major if key(newest) > key(cur) else ''}")
