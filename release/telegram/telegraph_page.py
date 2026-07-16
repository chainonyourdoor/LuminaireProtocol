import os
import sys
import json
import time
import urllib.request
import urllib.error

# ======================================================
# 📄 RELEASE — TELEGRAPH FEATURES PAGE
# ======================================================
# Creates a fresh Telegraph page for this release (never reused across
# releases — see the "bikin baru tiap release" decision: reusing one page
# would let historical Telegram channel posts silently drift, since anyone
# scrolling back and clicking an old "Features" link would see whatever the
# page currently says, not what was true when that post went out).
#
# This is a standalone script (not sourced) so it can be called once from
# channel_post.sh, before the channel caption is built, and its stdout
# captured directly as the page URL. Never causes the build/post to fail:
# on any error it prints an empty line to stdout and exits 0 — the caller
# (channel_post.sh) treats an empty result as "no Features link, fall back
# to the zip caption's Add-ons block" (see build_channel_caption() in
# caption.py).

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import caption  # noqa: E402  (path insert must happen first)

TELEGRAPH_API_TIMEOUT = int(os.environ.get("TELEGRAPH_API_TIMEOUT", "30"))
TELEGRAPH_MAX_RETRIES = int(os.environ.get("TELEGRAPH_MAX_RETRIES", "3"))


def eprint(msg):
    print(msg, file=sys.stderr, flush=True)


def build_title(env):
    linux_ver = env.get("LINUX_VER", "N/A")
    return f"LuminaireProtocol {linux_ver}"


def create_page(token, title, content):
    # No explicit author_name here — omitting it makes Telegraph fall back
    # to the account's own default author_name (set once at createAccount
    # time), instead of overriding it per-page with a hardcoded value.
    payload = json.dumps({
        "access_token": token,
        "title": title,
        "content": json.dumps(content),
        "return_content": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.telegra.ph/createPage",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    attempt = 1
    while attempt <= TELEGRAPH_MAX_RETRIES:
        try:
            with urllib.request.urlopen(req, timeout=TELEGRAPH_API_TIMEOUT) as resp:
                body = json.loads(resp.read().decode("utf-8"))
                if body.get("ok") and body.get("result", {}).get("url"):
                    return body["result"]["url"]
                eprint(f"[warn] telegraph_page: API returned non-ok body: {body}")
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError) as e:
            eprint(f"[warn] telegraph_page: attempt {attempt} failed: {e}")

        if attempt < TELEGRAPH_MAX_RETRIES:
            sleep_secs = 2 ** attempt
            eprint(f"[warn] telegraph_page: retrying in {sleep_secs}s...")
            time.sleep(sleep_secs)
        attempt += 1

    return None


def main():
    token = os.environ.get("TELEGRAPH_TOKEN", "").strip()
    if not token:
        eprint("[warn] telegraph_page: TELEGRAPH_TOKEN not set, skipping Features page")
        print("")
        return

    env = os.environ
    content = caption.build_telegraph_content(env)
    title = build_title(env)

    url = create_page(token, title, content)
    if url:
        eprint(f"[info] telegraph_page: page created \u2705 {url}")
        print(url)
    else:
        eprint("[warn] telegraph_page: giving up after retries, no Features link this run")
        print("")


if __name__ == "__main__":
    main()
