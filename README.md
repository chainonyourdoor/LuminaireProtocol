<div align="center">

<img src="https://raw.githubusercontent.com/primer/octicons/main/icons/cpu-24.svg" width="64" height="64" />

# ✨ LuminaireProtocol

**CI/build orchestration for the Luminaire Android GKI kernel**

[![Build](https://img.shields.io/github/actions/workflow/status/chainonyourdoor/LuminaireProtocol/build.yml?branch=main&label=build&logo=github&style=for-the-badge)](https://github.com/chainonyourdoor/LuminaireProtocol/actions/workflows/build.yml)
[![Telegram](https://img.shields.io/badge/Telegram-LuminaireGKI-blue?style=for-the-badge&logo=telegram)](https://t.me/LuminaireGKI)
[![License](https://img.shields.io/badge/license-GPL--2.0-green?style=for-the-badge)](LICENSE)

</div>

---

## 📖 What is this?

**LuminaireProtocol** is a build orchestration repository for the **Luminaire** Android GKI kernel.
This repo does **not** contain kernel source — it contains all the scripts and GitHub Actions workflows that:

1. Download the kernel source from `chainonyourdoor/android_kernel_common-*`
2. Apply patches, integrations, and addons
3. Build the kernel via **MAKE** or **KLEAF** (Bazel)
4. Package and release via AnyKernel3 + Telegram

---

## 🖥️ Supported Kernel Versions

- `6.1` — android14-6.1-lts ⭐ Currently Active
- `6.6` — android15-6.6-lts
- `6.12` — android16-6.12-lts
- `5.15` — android13-5.15-lts
- `5.10` — android13-5.10-lts

---

## ⚙️ Build Systems

- **MAKE** — Clang (Cirrus / Neutron / WeebX / ZyC) + ccache-ECS
- **KLEAF** — AOSP Clang prebuilt via Bazel + Bazel internal cache

---

## 🔑 Root Solutions

| Variant | KSU Fork | SuSFS |
|---------|----------|-------|
| `VANILLA` | — | — |
| `RESUKISU` | ReSukiSU | ✅ + Multi-Manager |
| `SUKISU` | SukiSU-Ultra | — |

---

## ⚡ Addons

- **BBG** — Baseband Guard LSM security module
- **BBRv3** — TCP BBRv3 congestion control backport
- **ZeroMount** — VFS path redirection engine (best paired with SuSFS)
- **NoMount** — VFS path injection framework
- **Re:Kernel** — Netlink event hook for binder/signal (frozen process detection)
- **Droidspaces** — LXC container runtime support

---

## 🙏 Credits

- [ccache-ECS](https://github.com/cctv18/ccache-ECS) — cctv18
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) — ReSukiSU Team
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) — SukiSU Team
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — simonpunk
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — osm0sis
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) — vc-teahouse
- [BBRv3 backport](https://github.com/WildKernels/kernel_patches/tree/main/common/bbrv3) — fatalcoder524
- [ZeroMount](https://github.com/Enginex0/zeromount) — Enginex0
- [NoMount](https://github.com/maxsteeel/nomount) — maxsteeel
- [Re:Kernel](https://github.com/Sakion-Team/Re-Kernel) — Sakion-Team
- [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) — greenforce-project
- [Neutron Clang](https://github.com/Neutron-Toolchains/clang-build-catalogue) — Neutron-Toolchains
- [WeebX Clang](https://github.com/XSans0/WeebX-Clang) — XSans0
- [ZyC Clang](https://github.com/ZyCromerZ/Clang) — ZyCromerZ

---

<div align="center">

Made with ❤️ by [chainonyourdoor](https://github.com/chainonyourdoor)

</div>
