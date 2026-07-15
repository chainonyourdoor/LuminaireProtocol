import os
import sys
import json
from datetime import datetime


CAPTION_LIMIT = 1024
PUSH_TEXT_LIMIT = 4096  # sendMessage text limit — separate from the 1024
                         # sendDocument/sendPhoto caption limit above

KERNEL_VERSION_TO_ANDROID = {
    "5.10": "12",
    "5.15": "13",
    "6.1":  "14",
    "6.6":  "15",
    "6.12": "16",
}

VARIANT_DISPLAY = {
    "VANILLA":        "Vanilla",
    "RESUKISU":       "ReSukiSU",
    "RESUKISU_SUSFS": "ReSukiSU\\+SUSFS",
    "SUKISU":         "SukiSU\\-Ultra",
    "SUKISU_SUSFS":   "SukiSU\\-Ultra\\+SUSFS",
    "KSUNEXT":        "KernelSU\\-Next",
    "KSUNEXT_SUSFS":  "KernelSU\\-Next\\+SUSFS",
}

# Single source of truth for addon display names — shared by build_blocks()
# (per-build group caption) and build_channel_caption() (channel post).
# Adding a new addon only means adding an entry here (+ TOGGLE_ADDON_ORDER
# below if it should show as an explicit Enable/Disable line in the group
# caption's Add-ons block).
ADDON_DISPLAY_NAMES = {
    "bbrv3":       "BBRv3",
    "bbg":         "BBG",
    "rekernel":    "Re:Kernel",
    "droidspaces": "Droidspaces",
    "zeromount":   "ZeroMount",
    "nomount":     "NoMount",
    "bore":        "BORE",
    "adios":       "ADIOS",
    "kasumi":      "Kasumi",
    "ntsync":      "NTSync",
    "ipset":       "IPSet",
}

# Mountless-engine addons are mutually exclusive (only one, or none, active
# per build) and shown as a single "Mountless Engine" line rather than their
# own Enable/Disable row.
MOUNTLESS_ADDON_TOKENS = ("nomount", "zeromount")

# Toggle-style addons shown as explicit Enable/Disable lines in the group
# caption, in display order.
TOGGLE_ADDON_ORDER = ["rekernel", "bbrv3", "bbg", "droidspaces", "bore", "adios", "kasumi", "ntsync", "ipset"]


def mdv2_escape(s):
    special = r"\_*[]()~`>#+-=|{}.!"
    for ch in special:
        s = s.replace(ch, "\\" + ch)
    return s


def mdv2_escape_url(s):
    s = s.replace("\\", "\\\\")
    s = s.replace(")", "\\)")
    return s


def html_escape(s):
    # Text-node escaping for Telegram HTML parse_mode — only & < > matter
    # here (no attribute context), order matters: & must go first or it
    # would double-escape the entities just inserted for < and >.
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def html_escape_attr(s):
    # Same as html_escape() plus quote-escaping, for use inside an
    # href="..." attribute value.
    return html_escape(s).replace('"', "&quot;")


def mdv2_code_escape(s):
    s = s.replace("\\", "\\\\")
    s = s.replace("`", "\\`")
    return s


def utf16_len(s):
    return sum(2 if ord(c) > 0xFFFF else 1 for c in s)


def truncate(caption, limit, suffix="\n\u2026\n```"):
    if utf16_len(caption) <= limit:
        return caption
    suffix_len = utf16_len(suffix)
    result = []
    current_len = 0
    for ch in caption:
        ch_len = 2 if ord(ch) > 0xFFFF else 1
        if current_len + ch_len + suffix_len > limit:
            break
        result.append(ch)
        current_len += ch_len
    return "".join(result) + suffix


def build_blocks(env):
    linux_ver       = mdv2_code_escape(env.get("LINUX_VER", "N/A"))
    build_system    = mdv2_code_escape(env.get("BUILD_SYSTEM_DISPLAY", "N/A"))
    compiler        = mdv2_code_escape(env.get("COMPILER_STRING", "N/A"))
    lto             = mdv2_code_escape(env.get("LTO_MODE", "NONE"))
    kernel_variant  = mdv2_code_escape(env.get("KERNEL_VARIANT_DISPLAY", "N/A"))
    susfs_ver       = mdv2_code_escape(env.get("SUSFS_VER", "N/A"))
    date_str        = mdv2_code_escape(datetime.now().strftime("%d %b %Y"))

    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    mountless = "N/A"
    for token in addon_tokens:
        if token in MOUNTLESS_ADDON_TOKENS:
            mountless = ADDON_DISPLAY_NAMES.get(token, token)
            break
    mountless = mdv2_code_escape(mountless)

    addon_status_lines = []
    for token in TOGGLE_ADDON_ORDER:
        name = ADDON_DISPLAY_NAMES.get(token, token)
        status = "Enable" if token in addon_tokens else "Disable"
        addon_status_lines.append(f"{name.ljust(16)} : {mdv2_code_escape(status)}")

    commit_short    = env.get("GITHUB_SHA", "")[:7]
    commit_url      = "{}/{}/commit/{}".format(
                        env.get("GITHUB_SERVER_URL", ""),
                        env.get("GITHUB_REPOSITORY", ""),
                        env.get("GITHUB_SHA", ""))
    run_url         = "{}/{}/actions/runs/{}".format(
                        env.get("GITHUB_SERVER_URL", ""),
                        env.get("GITHUB_REPOSITORY", ""),
                        env.get("GITHUB_RUN_ID", ""))
    run_id          = env.get("GITHUB_RUN_ID", "")

    block_luminaire = (
        "```Luminaire\n"
        f"Linux        : {linux_ver}\n"
        f"Build System : {build_system}\n"
        f"Compiler     : {compiler}\n"
        f"LTO          : {lto}\n"
        f"Date         : {date_str}```"
    )
    is_vanilla = env.get("KERNEL_VARIANT", "").upper() == "VANILLA"
    ksu_display = "N/A" if is_vanilla else kernel_variant
    ksu_version = mdv2_code_escape(env.get("KERNEL_VARIANT_VERSION", ""))
    root_lines = [f"KSU     : {ksu_display}"]
    if not is_vanilla and ksu_version:
        root_lines.append(f"Version : {ksu_version}")
    root_lines.append(f"SuSFS   : {susfs_ver}")
    if is_vanilla:
        root_lines.append("Vanilla Build")
    block_root = "```Root-solution\n" + "\n".join(root_lines) + "```"
    block_addons = (
        "```Add-ons\n"
        f"Mountless Engine : {mountless}\n"
        + "\n".join(addon_status_lines) +
        "```"
    )
    footer = "[{}]({}) \\| [Run \\#{}]({})".format(
        mdv2_escape(commit_short),
        mdv2_escape_url(commit_url),
        mdv2_escape(run_id),
        mdv2_escape_url(run_url),
    )

    return block_luminaire, block_root, block_addons, footer


CHANGELOG_MAX_LEN = 300


def build_push_caption(env):
    """
    Caption for the plain push-event notify (.github/workflows/notify.yml),
    distinct from build_blocks()/build_channel_caption() above (those are
    for release/test build posts, still MarkdownV2 — only the push notify
    uses HTML). Layout follows the redesign from commits b69f6bf/8a860ed
    (header line, Branch in inline code, Author linked, Title/Message as
    boxed blocks, Commit link as the closing line) — only the markup
    language changed from MarkdownV2 to HTML, the structure itself didn't.

    Uses HTML parse_mode instead of MarkdownV2: HTML only needs & < >
    escaped in text nodes, so a stray unescaped character can't silently
    break the whole message the way one missed MDv2 special char can.
    """
    branch_raw = env.get("BRANCH", "")
    author     = env.get("AUTHOR", "")
    author_url = html_escape_attr("https://t.me/{}".format(author))

    commit_short = env.get("COMMIT", "")[:7]
    commit_url   = html_escape_attr(env.get("URL", ""))

    title = env.get("TITLE", "")
    body  = env.get("BODY", "")

    head = "\n".join([
        "New Commit \U0001F4CC",
        "",
        f"Branch : <code>{html_escape(branch_raw)}</code>",
        f'Author : <a href="{author_url}">{html_escape(author)}</a>',
    ])
    # <pre><code class="language-X"> is how Telegram HTML gets the small
    # "language" label in the corner of the box — the same visual Telegram
    # gives a MarkdownV2 fenced block tagged ```X ... ``` (what b69f6bf
    # originally used). A plain <pre> alone doesn't carry that label.
    title_block = f'<pre><code class="language-Title">{html_escape(title)}</code></pre>'
    head_full = head + "\n" + title_block
    footer = f'\nCommit : <a href="{commit_url}">{html_escape(commit_short)}</a>'

    if not body.strip():
        return truncate(head_full + footer, PUSH_TEXT_LIMIT)

    # Budget the body block against what's left after head_full + footer +
    # the fixed wrapper tags, so truncate() never has to cut inside a
    # <pre>/<code> tag itself — only the escaped body shortens.
    wrapper = '\n<pre><code class="language-Message"></code></pre>'
    fixed_len = utf16_len(head_full) + utf16_len(footer) + utf16_len(wrapper)
    body_budget = PUSH_TEXT_LIMIT - fixed_len
    body_esc = html_escape(body)
    if utf16_len(body_esc) > body_budget:
        body_esc = truncate(body_esc, max(body_budget, 0), suffix="\n\u2026")

    message_block = f'<pre><code class="language-Message">{body_esc}</code></pre>'
    return head_full + "\n" + message_block + footer


def build_channel_caption(env, variant_links, variant_versions=None):
    """
    variant_links: dict { "VANILLA": "https://t.me/c/...", "RESUKISU_SUSFS": "...", ... }
    variant_versions: dict { "RESUKISU": "v4.1.0 (35002/2)", "SUKISU_SUSFS": "4.1.2 (40819/2)", ... } —
    optional. Keys match variant_links' keys exactly (including the _SUSFS
    suffix where applicable). All three forks resolve a version string
    (see resukisu.sh / sukisu.sh / ksunext.sh's "Version string" step);
    a fork only lacks an entry if that step itself failed to resolve anything.
    Only variants present in variant_links will be listed.
    """
    if variant_versions is None:
        variant_versions = {}
    kernel_ver  = env.get("KERNEL_VERSION", "")
    linux_ver   = env.get("LINUX_VER", "N/A")
    android_ver = KERNEL_VERSION_TO_ANDROID.get(kernel_ver, "?")

    # e.g. "6.1.174" -> "6.1.x"
    major_minor = ".".join(linux_ver.split(".")[:2]) + ".x"

    sections = [
        f"*Luminaire \\| Protocol \\| {mdv2_escape(linux_ver)}*\n"
        f"*GKI Kernel \\| Android {mdv2_escape(android_ver)} \\| Linux {mdv2_escape(major_minor)}*"
    ]

    # Add-ons — only the ones actually enabled for this run
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    if addon_tokens:
        addon_lines = ["*Add\\-ons*"]
        for token in addon_tokens:
            name = ADDON_DISPLAY_NAMES.get(token, token)
            addon_lines.append(f"\\- {mdv2_escape(name)}")
        sections.append("\n".join(addon_lines))

    # Download links
    download_lines = ["*Download*"]
    for variant_key, link in variant_links.items():
        display = VARIANT_DISPLAY.get(variant_key, mdv2_escape(variant_key))
        version = variant_versions.get(variant_key, "")
        if version:
            display = f"{display} \\- {mdv2_escape(version)}"
        safe_link = mdv2_escape_url(link)
        download_lines.append(f"• [{display}]({safe_link})")
    sections.append("\n".join(download_lines))

    # Changelog — manual input, optional, capped so it can't crowd out the
    # rest of the caption if someone pastes something huge. Rendered as a
    # code block, same style as the group caption's Root-solution/Add-ons
    # blocks, instead of plain bold text.
    changelog_raw = env.get("CHANGELOG", "").strip()
    if changelog_raw:
        entries = [e.strip() for e in changelog_raw.split(";") if e.strip()]
        changelog_body = "\n".join(f"- {mdv2_code_escape(entry)}" for entry in entries)
        changelog_block = "```Changelog\n" + changelog_body + "```"
        changelog_block = truncate(changelog_block, CHANGELOG_MAX_LEN)
        sections.append(changelog_block)

    # Traceability — commit + workflow run that produced this post
    commit_short = env.get("GITHUB_SHA", "")[:7]
    commit_url = "{}/{}/commit/{}".format(
        env.get("GITHUB_SERVER_URL", ""),
        env.get("GITHUB_REPOSITORY", ""),
        env.get("GITHUB_SHA", ""))
    commits_url = "{}/{}/commits/main/".format(
        env.get("GITHUB_SERVER_URL", ""),
        env.get("GITHUB_REPOSITORY", ""))
    run_url = "{}/{}/actions/runs/{}".format(
        env.get("GITHUB_SERVER_URL", ""),
        env.get("GITHUB_REPOSITORY", ""),
        env.get("GITHUB_RUN_ID", ""))
    trace_line = "[Commits]({}) \\| [Workflows]({})".format(
        mdv2_escape_url(commits_url), mdv2_escape_url(run_url))
    sections.append(trace_line)

    # Bug reports point to the community discussion group, not the CI group
    group_url = mdv2_escape_url("https://t.me/{}".format(env.get("TELEGRAM_GROUP", "")))
    sections.append(
        f"Found a bug? Let's discuss it in [Luminaire Lab]({group_url})"
    )

    date_str = mdv2_escape(datetime.now().strftime("%-d %b %Y"))
    donate_url = mdv2_escape_url("https://sociabuzz.com/chainonyourdoor")
    sections.append(f"{date_str} \u00b7 [Support]({donate_url})")

    sections.append("\\#GKI \\#Kernel \\#Luminaire")

    caption = "\n\n".join(sections)
    return truncate(caption, CAPTION_LIMIT)



def main():
    # Push-notify mode: `caption.py push <output_file>` — separate from the
    # release/test build mode below (2 positional args, no subcommand),
    # since it's a different caller (notify.yml) with a different env-var
    # shape (BRANCH/AUTHOR/COMMIT/URL/TITLE/BODY vs. the build-metadata
    # vars build_blocks()/build_channel_caption() expect).
    if len(sys.argv) == 3 and sys.argv[1] == "push":
        env = os.environ
        caption = build_push_caption(env)
        with open(sys.argv[2], "w") as f:
            f.write(caption)
        print("[info] telegram_caption: push caption written ✅", flush=True)
        return

    out_group   = sys.argv[1]
    out_channel = sys.argv[2]

    env = os.environ

    block_luminaire, block_root, block_addons, footer = build_blocks(env)

    caption_group = "\n".join([block_luminaire, block_root, block_addons, footer])
    caption_group = truncate(caption_group, CAPTION_LIMIT)

    # Channel caption — built from VARIANT_LINKS_JSON (provided by channel_post.sh)
    variant_links_json = env.get("VARIANT_LINKS_JSON", "")
    try:
        variant_links = json.loads(variant_links_json) if variant_links_json else {}
    except Exception:
        variant_links = {}

    variant_versions_json = env.get("VARIANT_VERSIONS_JSON", "")
    try:
        variant_versions = json.loads(variant_versions_json) if variant_versions_json else {}
    except Exception:
        variant_versions = {}

    caption_channel = build_channel_caption(env, variant_links, variant_versions)

    with open(out_group, "w") as f:
        f.write(caption_group)

    with open(out_channel, "w") as f:
        f.write(caption_channel)

    print("[info] telegram_caption: captions written ✅", flush=True)


if __name__ == "__main__":
    main()
