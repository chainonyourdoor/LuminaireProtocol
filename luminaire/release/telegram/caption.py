import os
import sys
from datetime import datetime


CAPTION_LIMIT = 1024


def mdv2_escape(s):
    special = r"\_*[]()~`>#+-=|{}.!"
    for ch in special:
        s = s.replace(ch, "\\" + ch)
    return s


def mdv2_escape_url(s):
    s = s.replace("\\", "\\\\")
    s = s.replace(")", "\\)")
    return s


def mdv2_code_escape(s):
    s = s.replace("\\", "\\\\")
    s = s.replace("`", "\\`")
    return s


def utf16_len(s):
    return sum(2 if ord(c) > 0xFFFF else 1 for c in s)


def truncate(caption, limit):
    if utf16_len(caption) <= limit:
        return caption
    suffix = "\n\u2026\n```"
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
    kernel_branch   = mdv2_code_escape(env.get("KERNEL_BRANCH", "N/A"))
    build_system    = mdv2_code_escape(env.get("BUILD_SYSTEM_DISPLAY", "N/A"))
    compiler        = mdv2_code_escape(env.get("COMPILER_STRING", "N/A"))
    lto             = mdv2_code_escape(env.get("ENABLE_LTO", "NONE"))
    root_solution   = mdv2_code_escape(env.get("ROOT_SOLUTION_DISPLAY", "N/A"))
    susfs_ver       = mdv2_code_escape(env.get("SUSFS_VER", "N/A"))
    mountless       = mdv2_code_escape(env.get("MOUNTLESS_DISPLAY", "N/A"))
    rekernel        = mdv2_code_escape(env.get("REKERNEL_DISPLAY", "Disable"))
    bbg             = mdv2_code_escape(env.get("BBG_DISPLAY", "Disable"))
    droidspaces     = mdv2_code_escape(env.get("DROIDSPACES_DISPLAY", "Disable"))
    date_str        = mdv2_code_escape(datetime.now().strftime("%d %b %Y"))

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
        f"Date         : {date_str}\n"
        "```"
    )
    is_vanilla = env.get("ROOT_SOLUTION", "").upper() == "VANILLA"
    ksu_display = "N/A" if is_vanilla else root_solution
    block_root = (
        "```Root-Solution\n"
        f"KSU   : {ksu_display}\n"
        f"SuSFS : {susfs_ver}\n"
        + ("Note  : Vanilla build, get your root via KSU LKM or Magisk\n" if is_vanilla else "")
        + "```"
    )
    block_addons = (
        "```Add-ons\n"
        f"Mountless Engine : {mountless}\n"
        f"Re:Kernel        : {rekernel}\n"
        f"BBG              : {bbg}\n"
        f"Droidspaces      : {droidspaces}\n"
        "```"
    )
    footer = "[{}]({}) \\| [Run \\#{}]({})".format(
        mdv2_escape(commit_short),
        mdv2_escape_url(commit_url),
        mdv2_escape(run_id),
        mdv2_escape_url(run_url),
    )

    return block_luminaire, block_root, block_addons, footer


def main():
    out_group   = sys.argv[1]
    out_channel = sys.argv[2]

    env = os.environ

    block_luminaire, block_root, block_addons, footer = build_blocks(env)

    caption_group = "\n".join([block_luminaire, block_root, block_addons, footer])
    caption_group = truncate(caption_group, CAPTION_LIMIT)

    donate_url  = mdv2_escape_url("https://sociabuzz.com/chainonyourdoor")
    donate_line = (
        "*My dev partner insists on being paid in Whiskas\\. "
        "If this kernel's been useful, maybe help me keep the little engineer fed?* \U0001f431"
    )
    donate_link = f"[Buy the cat some Whiskas]({donate_url})"

    caption_channel = "\n".join([
        block_luminaire, block_root, block_addons, footer,
        "", donate_line, donate_link,
    ])
    caption_channel = truncate(caption_channel, CAPTION_LIMIT)

    with open(out_group, "w") as f:
        f.write(caption_group)

    with open(out_channel, "w") as f:
        f.write(caption_channel)

    print("[info] telegram_caption: captions written ✅", flush=True)


if __name__ == "__main__":
    main()
