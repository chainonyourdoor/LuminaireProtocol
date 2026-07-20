<div align="center">

<img src="https://raw.githubusercontent.com/primer/octicons/main/icons/cpu-24.svg" width="64" height="64" />

# LuminaireProtocol

**CI/build orchestration for the Luminaire Android GKI kernel**

[![Build](https://img.shields.io/github/actions/workflow/status/chainonyourdoor/LuminaireProtocol/build.yml?branch=main&label=build&logo=github&style=for-the-badge)](https://github.com/chainonyourdoor/LuminaireProtocol/actions/workflows/build.yml)
[![Telegram](https://img.shields.io/badge/Telegram-Luminaire-blue?style=for-the-badge&logo=telegram)](https://t.me/LuminaireProtocol)
</div>

---

## 📖 What is this?

**LuminaireProtocol** is a build orchestration repository for the **Luminaire** Android GKI kernel.
This repo does **not** contain kernel source — it contains all the scripts and GitHub Actions workflows that:

1. Download the kernel source from `chainonyourdoor/LuminaireKernel-*`
2. Apply patches, integrations, and addons
3. Build the kernel via **MAKE**
4. Package and release via AnyKernel3 + Telegram

---

## Build System

- **MAKE** — Clang (AOSP / Cirrus / Neutron / WeebX / ZyC) + ccache-ECS

---

## Credits

- [ccache-ECS](https://github.com/cctv18/ccache-ECS) — cctv18
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — osm0sis
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) — ReSukiSU Team
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) — SukiSU Team
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — KernelSU-Next Team
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — simonpunk
- [AOSP Clang mirror](https://github.com/bachnxuan/aosp_clang_mirror) — bachnxuan
- [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) — greenforce-project
- [Neutron Clang](https://github.com/Neutron-Toolchains/clang-build-catalogue) — Neutron-Toolchains
- [WeebX Clang](https://github.com/XSans0/WeebX-Clang) — XSans0
- [ZyC Clang](https://github.com/ZyCromerZ/Clang) — ZyCromerZ

---

## License

feel free to fork and modify — a credit/link back is appreciated
nah i'm kidding, do what the fuck u want, idc
