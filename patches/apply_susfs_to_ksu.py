#!/usr/bin/env python3
"""Apply SUSFS changes to KernelSU-Next source programmatically."""

import re, sys, os

KSU_DIR = sys.argv[1] if len(sys.argv) > 1 else "."

def read(path):
    with open(os.path.join(KSU_DIR, path)) as f:
        return f.read()

def write(path, content):
    with open(os.path.join(KSU_DIR, path), 'w') as f:
        f.write(content)

def replace(path, old, new, required=True):
    content = read(path)
    if old in content:
        write(path, content.replace(old, new, 1))
        print(f"[OK] {path}")
        return True
    if required:
        print(f"[WARN] {path}: pattern not found")
    return False

# ── kernel/core/init.c ────────────────────────────────────────────
content = read("kernel/core/init.c")

# Fix includes
content = content.replace('#include "hook/syscall_hook_manager.h"\n', '')
content = content.replace('#include "hook/lsm_hook.h"\n', '')
content = content.replace('#include "hook/syscall_hook.h"\n',
                           '#include "hook/setuid_hook.h"\n#include "feature/sucompat.h"\n')
content = content.replace('#include "feature/selinux_hide.h"\n', '')

# Remove x86 cpufeature block
content = re.sub(
    r'#if defined\(__x86_64__\)\n#include <asm/cpufeature\.h>.*?#endif\n\n',
    '', content, flags=re.DOTALL, count=1)

# Remove ksu_late_loaded global
content = content.replace('bool ksu_late_loaded;\n\n', '')

# Remove x86 runtime check
content = re.sub(
    r'#if defined\(__x86_64__\)\n    // If the kernel.*?#endif\n\n',
    '', content, flags=re.DOTALL, count=1)

# Remove ksu_late_loaded assignment
content = re.sub(
    r'#ifdef MODULE\n\tksu_late_loaded = \(current->pid != 1\);\n#else\n\tksu_late_loaded = false;\n#endif\n\n',
    '', content, count=1)

# Add susfs_init before prepare_creds
if 'susfs_init()' not in content:
    content = content.replace(
        '    ksu_cred = prepare_creds();',
        '#ifdef CONFIG_KSU_SUSFS\n    susfs_init();\n#endif\n\n    ksu_cred = prepare_creds();',
        1)

# Remove syscall_hook_init
content = content.replace('\n\tksu_syscall_hook_init();\n', '\n')

# Add sucompat_init + setuid_hook_init
if 'ksu_sucompat_init' not in content:
    content = content.replace(
        '\tksu_feature_init();\n',
        '\tksu_feature_init();\n\n    ksu_sucompat_init();\n\n\tksu_setuid_hook_init();\n')

# Remove lsm/selinux inits
content = content.replace('\n\tksu_lsm_hook_init();\n', '\n')
content = content.replace('\n\tksu_selinux_hide_init();\n', '\n')

# Simplify late_loaded if/else
if 'ksu_late_loaded' in content:
    m = re.search(r'\tif \(ksu_late_loaded\) \{.*?\} else \{.*?\}\n', content, re.DOTALL)
    if m:
        simple = ('\tksu_allowlist_init();\n\n'
                  '\tksu_throne_tracker_init();\n\n'
                  '\tksu_ksud_init();\n\n'
                  '\tksu_file_wrapper_init();\n')
        content = content[:m.start()] + simple + content[m.end():]

# Remove MODULE/kobject_del block
content = re.sub(
    r'#ifdef MODULE\n#ifndef CONFIG_KSU_DEBUG\n\tkobject_del.*?#endif\n#endif\n',
    '', content, flags=re.DOTALL)

# Fix exit function
content = content.replace(
    '\t// Phase 1: Stop all hooks first to prevent new callbacks\n\tksu_syscall_hook_manager_exit();\n\n', '')
content = re.sub(r'\tif \(!ksu_late_loaded\)\n\t\tksu_ksud_exit\(\);\n',
                  '\tksu_ksud_exit();\n', content)
content = content.replace('\t// Phase 2: Now safe to release data structures\n',
                           '\t// Now safe to release data structures\n')
content = content.replace('\n\tksu_selinux_hide_exit();\n', '')
content = content.replace('\n\tksu_lsm_hook_exit();\n', '')

write("kernel/core/init.c", content)
print("[OK] kernel/core/init.c")

# ── kernel/policy/allowlist.c ─────────────────────────────────────
content = read("kernel/policy/allowlist.c")
changed = False
for pat in [
    re.compile(r'[ \t]+if \(likely\(ksu_is_manager_appid_valid\(\)\)[^}]+return false;\n[ \t]+\}\n', re.DOTALL),
    re.compile(r'[ \t]+if \(unlikely\(uid == WEBVIEW_ZYGOTE_UID\)\)[^}]+return false;\n[ \t]+\}\n', re.DOTALL),
]:
    if pat.search(content):
        content = pat.sub('', content, count=1)
        changed = True
if changed:
    write("kernel/policy/allowlist.c", content)
    print("[OK] kernel/policy/allowlist.c")
else:
    print("[WARN] kernel/policy/allowlist.c: patterns not found")

# ── kernel/policy/app_profile.c ──────────────────────────────────
replace("kernel/policy/app_profile.c",
        '#include "hook/tp_marker.h"\n', '')

print("\n[DONE] All SUSFS changes applied to KernelSU-Next")
