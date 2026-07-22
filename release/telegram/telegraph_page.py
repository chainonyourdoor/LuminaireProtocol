import os
import sys
import json
import time
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import caption  # noqa: E402

TELEGRAPH_API_TIMEOUT = int(os.environ.get("TELEGRAPH_API_TIMEOUT", "30"))
TELEGRAPH_MAX_RETRIES = int(os.environ.get("TELEGRAPH_MAX_RETRIES", "3"))


def eprint(msg):
    print(msg, file=sys.stderr, flush=True)


def build_title(env):
    linux_ver = env.get("LINUX_VER", "N/A")
    return f"LuminaireProtocol {linux_ver}"


def create_page(token, title, content):
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
