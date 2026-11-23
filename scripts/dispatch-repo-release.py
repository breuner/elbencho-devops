#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Dispatch elbencho-repo-release.yml and wait until that run finishes.
# GITHUB_DISPATCH_TOKEN is a fine-grained token that can only start workflows
# in breuner/elbencho-devops.

import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

REPO = "breuner/elbencho-devops"
WORKFLOW = "elbencho-repo-release.yml"
REF = "main"
API = "https://api.github.com"
FIND_RUN_SECONDS = 180
POLL_SECONDS = 60
WAIT_MINUTES = 420


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def request(token, method, url, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
            payload = json.loads(raw) if raw else None
            return resp.status, payload
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        fail(f"GitHub API {method} {url} returned {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        fail(f"GitHub API {method} {url} failed: {exc.reason}")


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def main():
    token = os.environ.get("GITHUB_DISPATCH_TOKEN", "")
    tag = os.environ.get("GIT_TAG", "").strip()

    if not token:
        fail("GITHUB_DISPATCH_TOKEN is not set")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", tag):
        fail("GIT_TAG is empty or contains unsupported characters")

    run_name = f"Repo {tag}"
    started = datetime.now(timezone.utc)
    status, _payload = request(
        token,
        "POST",
        f"{API}/repos/{REPO}/actions/workflows/{WORKFLOW}/dispatches",
        {"ref": REF, "inputs": {"tag": tag}},
    )
    if status != 204:
        fail(f"workflow dispatch returned HTTP {status}")

    print(f"Dispatched {WORKFLOW} on {REF}: {run_name}", flush=True)
    print(
        f"https://github.com/{REPO}/actions/workflows/{WORKFLOW}",
        flush=True,
    )

    run = None
    deadline = time.time() + FIND_RUN_SECONDS
    while time.time() < deadline and run is None:
        time.sleep(5)
        _status, payload = request(
            token,
            "GET",
            f"{API}/repos/{REPO}/actions/workflows/{WORKFLOW}/runs"
            "?event=workflow_dispatch&per_page=20",
        )
        matches = []
        for candidate in payload.get("workflow_runs", []):
            name = candidate.get("name") or ""
            if name != run_name:
                continue
            created = parse_time(candidate["created_at"])
            if created < started - timedelta(seconds=30):
                continue
            matches.append(candidate)
        if matches:
            run = max(matches, key=lambda item: item["created_at"])

    if run is None:
        fail("the dispatched workflow run did not appear")

    run_id = run["id"]
    print(f"Workflow run: https://github.com/{REPO}/actions/runs/{run_id}", flush=True)

    wait_until = time.time() + WAIT_MINUTES * 60
    while time.time() < wait_until:
        _status, current = request(token, "GET", f"{API}/repos/{REPO}/actions/runs/{run_id}")
        run_status = current.get("status")
        conclusion = current.get("conclusion")
        print(f"status={run_status} conclusion={conclusion}", flush=True)
        if run_status == "completed":
            if conclusion == "success":
                print("Workflow succeeded.")
                return
            fail(f"workflow concluded with {conclusion}")
        time.sleep(POLL_SECONDS)

    fail(f"timed out after {WAIT_MINUTES} minutes")


if __name__ == "__main__":
    main()
