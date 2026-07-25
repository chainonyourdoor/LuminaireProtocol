import os
import sys
import json


CAPTION_LIMIT = 1024
PUSH_TEXT_LIMIT = 4096


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


ADDON_DISPLAY_NAMES = {
    "bbrv3":       "BBRv3",
    "bbg":         "BBG",
    "rekernel":    "Re:Kernel",
    "droidspaces": "Droidspaces",
    "zeromount":   "ZeroMount",
    "nomount":     "NoMount",
    "kasumi":      "Kasumi",
    "ntsync":      "NTSync",
    "wireguard":   "WireGuard",
    "lz4zstd":     "LZ4+ZSTD",
    "lz4kd":       "LZ4KD",
}


def addon_order(env):
    """Full addon catalog (toggle + mountless-engine addons together),
    read from ADDON_ORDER — exported by kernel/addons/registry.sh so
    this list never needs editing here just because an addon was
    added/removed there. See core_patch_order() above for the same
    pattern applied to kernel/luminaire/ features."""
    raw = env.get("ADDON_ORDER", "")
    order = [t for t in raw.split(",") if t]
    if order:
        return order
    # Fallback if ADDON_ORDER wasn't exported (older workflow run):
    # degrades gracefully to only the addons actually touched this
    # build — addons the user didn't select at all won't show as an
    # explicit "Disable" line, unlike the normal path.
    applied = [t for t in env.get("APPLIED_ADDONS", "").split(",") if t]
    skipped = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    return applied + skipped


def addon_mountless_tokens(env):
    raw = env.get("ADDON_MOUNTLESS_TOKENS", "")
    tokens = [t for t in raw.split(",") if t]
    return tuple(tokens) if tokens else ("nomount", "zeromount")


def toggle_addon_order(env):
    """addon_order() minus the mountless-engine addons, which are
    shown as a single 'Mountless Engine' line instead of their own
    Enable/Disable row."""
    mountless = set(addon_mountless_tokens(env))
    return [t for t in addon_order(env) if t not in mountless]


def addon_display_name(token):
    if token in ADDON_DISPLAY_NAMES:
        return ADDON_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))


def resolve_mountless_engine(env):
    """Which mountless-engine addon (if any) is active this build, as
    its display name, or 'None'. Shared by build_blocks() (group
    caption's dedicated "Mountless Engine" line) and
    build_telegraph_content() (same info, as a row in the Optional
    Add-ons table — see that function for why it needs its own row
    instead of relying on toggle_addon_order(), which deliberately
    excludes mountless tokens from the regular Enable/Disable rows)."""
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    mountless_tokens = addon_mountless_tokens(env)
    for token in addon_tokens:
        if token in mountless_tokens and token not in skipped_tokens:
            return addon_display_name(token)
    return "None"


CORE_PATCH_DISPLAY_NAMES = {
    "bore":                     "BORE",
    "adios":                    "ADIOS",
    "workqueue_catchup":        "Workqueue Catch-up",
    "schedutil_catchup":        "Schedutil Catch-up",
    "ufs_writebooster_catchup": "UFS WriteBooster Catch-up",
}


def core_patch_order(env):
    """The full set+order of kernel/luminaire/ features (applied AND
    skipped this build), read from LUMINAIRE_FEATURE_ORDER — exported
    by kernel/luminaire/registry.sh so this list never needs editing
    here just because a feature was added/removed there."""
    raw = env.get("LUMINAIRE_FEATURE_ORDER", "")
    order = [t for t in raw.split(",") if t]
    if order:
        return order
    # Fallback if LUMINAIRE_FEATURE_ORDER wasn't exported (older
    # workflow run, or manual/local testing): best-effort reconstruct
    # from the two lists that are always present.
    applied = [t for t in env.get("APPLIED_LUMINAIRE", "").split(",") if t]
    skipped = [t for t in env.get("SKIPPED_LUMINAIRE", "").split(",") if t]
    return applied + skipped


def core_patch_display_name(token):
    if token in CORE_PATCH_DISPLAY_NAMES:
        return CORE_PATCH_DISPLAY_NAMES[token]
    return " ".join(w.capitalize() for w in token.split("_"))


def core_patch_status_plain(env, token, skipped_tokens):
    """Plain-text status for the Markdown code-block caption. Shows the
    active patch version (e.g. 'v6.8.0-rc1') when the feature's .sh
    script exported one via f"{TOKEN}_VERSION" (see BORE_VERSION in
    kernel/luminaire/bore/bore.sh) instead of a generic 'Active', since
    for versioned features like BORE which version is running is the
    actually useful information."""
    if token in skipped_tokens:
        return "N/A"
    version = env.get(f"{token.upper()}_VERSION", "").strip()
    return version if version else "Active"


FRAGMENT_FEATURES = {
    "Filesystem": [
        "Mountify / OverlayFS",
        "F2FS Extended Attributes",
        "POSIX ACL",
    ],
    "Memory": [
        "ZRAM (LZ4 compression)",
        "Memory Tracking",
        "Writeback Support",
    ],
    "CPU & Scheduler": [
        "Ondemand Governor (included)",
        "Frame Warning Disabled",
        "I/O Scheduler (MQ-Deadline, Kyber)",
    ],
    "Network": [
        "TCP Congestion Control (BBR, BIC, CUBIC, Westwood, HTCP)",
        "Network Schedulers (FQ, FQ_CoDel, CAKE, PIE, FQ-PIE)",
        "IP Set",
        "IPv6 NAT",
        "TTL Target (Netfilter)",
    ],
    "Debug": [
        "Full Kallsyms",
        "UBSAN Disabled",
        "Page Owner Disabled",
        "RCU Trace Disabled",
    ],
}


LTO_DISPLAY = {
    "NONE": "None",
    "THIN": "ThinLTO",
    "FULL": "FullLTO",
}


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
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def html_escape_attr(s):
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


def kernel_source_repo(kernel_ver):
    return f"LuminaireKernel-{kernel_ver}" if kernel_ver else "N/A"


def build_blocks(env):
    linux_ver       = mdv2_code_escape(env.get("LINUX_VER", "N/A"))
    kernel_ver      = env.get("KERNEL_VERSION", "")
    source_str      = mdv2_code_escape(kernel_source_repo(kernel_ver))
    kernel_branch   = mdv2_code_escape(env.get("KERNEL_BRANCH", "N/A"))
    compiler        = mdv2_code_escape(env.get("COMPILER_STRING", "N/A"))
    lto             = mdv2_code_escape(env.get("LTO_MODE", "NONE"))
    kernel_variant  = mdv2_code_escape(env.get("KERNEL_VARIANT_DISPLAY", "N/A"))
    susfs_ver       = mdv2_code_escape(env.get("SUSFS_VER", "N/A"))
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    mountless = mdv2_code_escape(resolve_mountless_engine(env))
    toggle_order = toggle_addon_order(env)
    # +1 for the trailing space before ":". "Mountless Engine" is
    # included here too since it shares this column via the hardcoded
    # line below — otherwise its colon drifts out of alignment
    # whenever every addon's display name is shorter than 16 chars.
    addon_name_width = max(
        [len(addon_display_name(t)) for t in toggle_order] + [len("Mountless Engine")]
    ) + 1
    addon_status_lines = []
    for token in toggle_order:
        name = addon_display_name(token)
        if token in skipped_tokens:
            status = "N/A"
        elif token in addon_tokens:
            status = "Enable"
        else:
            status = "Disable"
        addon_status_lines.append(f"{name.ljust(addon_name_width)}: {mdv2_code_escape(status)}")
    core_patch_tokens = [t for t in env.get("APPLIED_LUMINAIRE", "").split(",") if t]
    core_patch_skipped_tokens = [t for t in env.get("SKIPPED_LUMINAIRE", "").split(",") if t]
    core_patch_order_list = core_patch_order(env)
    # Separate width from the addons block's fixed 16 — core patch
    # names (e.g. "UFS WriteBooster Catch-up") can run longer than any
    # addon name, and a shared fixed width would misalign the colons.
    core_patch_name_width = max((len(core_patch_display_name(t)) for t in core_patch_order_list), default=16) + 1
    core_patch_status_lines = []
    for token in core_patch_order_list:
        name = core_patch_display_name(token)
        status = core_patch_status_plain(env, token, core_patch_skipped_tokens)
        core_patch_status_lines.append(f"{name.ljust(core_patch_name_width)}: {mdv2_code_escape(status)}")
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
        f"Kernel    : Linux {linux_ver}\n"
        f"Source    : {source_str}\n"
        f"Branch    : {kernel_branch}\n"
        f"Toolchain : {compiler}\n"
        f"LTO       : {lto}```"
    )
    is_vanilla = env.get("KERNEL_VARIANT", "").upper() == "VANILLA"
    if is_vanilla:
        root_lines = [
            "Version : Vanilla",
            "SuSFS   : N/A (Vanilla)",
        ]
    else:
        ksu_version = mdv2_code_escape(env.get("KERNEL_VARIANT_VERSION", "")) or "N/A"
        root_lines = [
            f"Version : {ksu_version}",
            f"SuSFS   : {susfs_ver}",
        ]
    variant_label = "Vanilla" if is_vanilla else kernel_variant
    block_root = f"```{variant_label}\n" + "\n".join(root_lines) + "```"
    block_addons = (
        "```Add-ons\n"
        f"{'Mountless Engine'.ljust(addon_name_width)}: {mountless}\n"
        + "\n".join(addon_status_lines) +
        "```"
    )
    has_active_core_patch = any(t not in core_patch_skipped_tokens for t in core_patch_order_list)
    if has_active_core_patch:
        block_core_patch = (
            "```Core-Patch\n"
            + "\n".join(core_patch_status_lines) +
            "```"
        )
    else:
        block_core_patch = None
    footer = "[{}]({}) \\| [Run \\#{}]({})".format(
        mdv2_escape(commit_short),
        mdv2_escape_url(commit_url),
        mdv2_escape(run_id),
        mdv2_escape_url(run_url),
    )
    return block_luminaire, block_root, block_core_patch, block_addons, footer


def build_telegraph_content(env):
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    skipped_tokens = [t for t in env.get("SKIPPED_ADDONS", "").split(",") if t]
    core_patch_tokens = [t for t in env.get("APPLIED_LUMINAIRE", "").split(",") if t]
    core_patch_skipped_tokens = [t for t in env.get("SKIPPED_LUMINAIRE", "").split(",") if t]
    kernel_ver  = env.get("KERNEL_VERSION", "")
    linux_ver   = env.get("LINUX_VER", "N/A")
    source_str  = kernel_source_repo(kernel_ver)
    compiler_string = env.get("COMPILER_STRING", "") or "N/A"
    lto_raw         = env.get("LTO_MODE", "")
    lto_display     = LTO_DISPLAY.get(lto_raw, lto_raw or "N/A")
    intro = (
        f"Luminaire Protocol \u2014 an Android GKI kernel build. This page "
        f"lists every feature and addon available as of this release; "
        f"addon status reflects this specific build."
    )
    overview_lines = [
        f"Kernel    : Linux {linux_ver}",
        f"Source    : {source_str}",
        f"Toolchain : {compiler_string}",
        f"LTO       : {lto_display}",
    ]
    overview_children = []
    for i, line in enumerate(overview_lines):
        if i > 0:
            overview_children.append({"tag": "br"})
        overview_children.append(line)
    overview_block = {
        "tag": "pre",
        "children": [{"tag": "code", "children": overview_children}],
    }
    content = [
        {"tag": "p", "children": [intro]},
        {"tag": "h3", "children": ["Overview"]},
        overview_block,
        {"tag": "h3", "children": ["Core Features"]},
        {"tag": "p", "children": ["Always available on every Luminaire build."]},
    ]
    for category, items in FRAGMENT_FEATURES.items():
        content.append({"tag": "h4", "children": [category]})
        content.append({
            "tag": "ul",
            "children": [{"tag": "li", "children": [item]} for item in items],
        })
    def addon_status_icon(token):
        if token in skipped_tokens:
            return "\u2796"
        return "\u2705" if token in addon_tokens else "\u274c"
    def core_patch_status_display(token):
        """Same version-aware status as core_patch_status_plain, but
        prefixed with the check/dash icon to match this table's style
        (see make_status_table below, shared with the addons table)."""
        if token in core_patch_skipped_tokens:
            return "\u2796 N/A"
        version = env.get(f"{token.upper()}_VERSION", "").strip()
        return f"\u2705 {version}" if version else "\u2705"
    def make_status_table(rows):
        name_width = max(len(name) for name, _ in rows) + 2
        lines = [f"{'Feature'.ljust(name_width)}Status"]
        lines += [f"{name.ljust(name_width)}{status}" for name, status in rows]
        children = []
        for i, line in enumerate(lines):
            if i > 0:
                children.append({"tag": "br"})
            children.append(line)
        return {"tag": "pre", "children": [{"tag": "code", "children": children}]}
    core_patch_rows = [
        (core_patch_display_name(token), core_patch_status_display(token))
        for token in core_patch_order(env)
    ]
    content.append({"tag": "h3", "children": ["Luminaire Features"]})
    content.append({"tag": "p", "children": ["Always-on, no toggle — active whenever this kernel version has the backport."]})
    content.append(make_status_table(core_patch_rows))
    addon_rows = [
        (addon_display_name(token), addon_status_icon(token))
        for token in toggle_addon_order(env)
    ]
    # toggle_addon_order() deliberately excludes nomount/zeromount (see
    # its docstring) since they're mutually-exclusive variants of one
    # choice, not independent toggles — but that choice still needs to
    # be visible somewhere on this page, or a build with e.g. ZeroMount
    # active would show literally no trace of it here. Appended as its
    # own row (status is a name, not an icon, same precedent as the
    # Luminaire Features table's version strings above) rather than
    # showing nomount/zeromount as two more icon rows, since "which one
    # of these two mutually-exclusive options is active" reads clearer
    # as one line than as a ✅/❌ pair.
    addon_rows.append(("Mountless Engine", resolve_mountless_engine(env)))
    content.append({"tag": "h3", "children": ["Optional Add-ons"]})
    content.append(make_status_table(addon_rows))
    return content


CHANGELOG_MAX_LEN = 300


def build_push_caption(env):
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
    title_block = f'<pre><code class="language-Title">{html_escape(title)}</code></pre>'
    head_full = head + "\n" + title_block
    footer = f'\nCommit : <a href="{commit_url}">{html_escape(commit_short)}</a>'
    if not body.strip():
        return truncate(head_full + footer, PUSH_TEXT_LIMIT)
    wrapper = '\n<pre><code class="language-Message"></code></pre>'
    fixed_len = utf16_len(head_full) + utf16_len(footer) + utf16_len(wrapper)
    body_budget = PUSH_TEXT_LIMIT - fixed_len
    body_esc = html_escape(body)
    if utf16_len(body_esc) > body_budget:
        body_esc = truncate(body_esc, max(body_budget, 0), suffix="\n\u2026")
    message_block = f'<pre><code class="language-Message">{body_esc}</code></pre>'
    return head_full + "\n" + message_block + footer


def build_channel_caption(env, variant_links, variant_versions=None):
    if variant_versions is None:
        variant_versions = {}
    kernel_ver  = env.get("KERNEL_VERSION", "")
    linux_ver   = env.get("LINUX_VER", "N/A")
    android_ver = KERNEL_VERSION_TO_ANDROID.get(kernel_ver, "?")
    major_minor = ".".join(linux_ver.split(".")[:2]) + ".x"
    sections = [
        f"*Luminaire \\| Protocol \\| {mdv2_escape(linux_ver)}*\n"
        f"*GKI Kernel \\| Android {mdv2_escape(android_ver)} \\| Linux {mdv2_escape(major_minor)}*"
    ]
    features_url = env.get("FEATURES_URL", "").strip()
    if features_url:
        sections.append(f"[What's Inside?]({mdv2_escape_url(features_url)})")
    else:
        sections.append("What's Inside?: see Add\\-ons block in the zip's caption")
    download_lines = ["*Download*"]
    variant_items = list(variant_links.items())
    for i, (variant_key, link) in enumerate(variant_items):
        display = VARIANT_DISPLAY.get(variant_key, mdv2_escape(variant_key))
        version = variant_versions.get(variant_key, "")
        if version:
            display = f"{display} \\- {mdv2_escape(version)}"
        safe_link = mdv2_escape_url(link)
        download_lines.append(f">• [{display}]({safe_link})")
        if i < len(variant_items) - 1:
            download_lines.append(">")
    sections.append("\n".join(download_lines))
    changelog_added = False
    changelog_raw = env.get("CHANGELOG", "").strip()
    if changelog_raw:
        entries = [e.strip() for e in changelog_raw.split(";") if e.strip()]
        changelog_body = "\n".join(f"- {mdv2_code_escape(entry)}" for entry in entries)
        changelog_block = "```Changelog\n" + changelog_body + "```"
        changelog_block = truncate(changelog_block, CHANGELOG_MAX_LEN)
        sections.append(changelog_block)
        changelog_added = True
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
    if changelog_added:
        sections[-1] = sections[-1] + "\n" + trace_line
    else:
        sections.append(trace_line)
    donate_url = mdv2_escape_url("https://sociabuzz.com/chainonyourdoor")
    sections.append(f"[Support]({donate_url})")
    group_url = mdv2_escape_url("https://t.me/{}".format(env.get("TELEGRAM_GROUP", "")))
    sections.append(
        "If you encounter any issues or unexpected behavior, please "
        f"report them through the [Luminaire Lab]({group_url}) "
        "discussion group\\."
    )
    sections.append("\\#GKI \\#Kernel \\#Luminaire")
    caption = "\n\n".join(sections)
    return truncate(caption, CAPTION_LIMIT)


def main():
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
    block_luminaire, block_root, block_core_patch, block_addons, footer = build_blocks(env)
    caption_group = "\n".join(
        b for b in [block_luminaire, block_root, block_core_patch, block_addons, footer] if b is not None
    )
    caption_group = truncate(caption_group, CAPTION_LIMIT)
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
