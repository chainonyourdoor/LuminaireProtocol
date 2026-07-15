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
3. Build the kernel via **MAKE** or **KLEAF** (Bazel)
4. Package and release via AnyKernel3 + Telegram

---

## ⚙️ Build Systems

- **MAKE** — Clang (Cirrus / Neutron / WeebX / ZyC) + ccache-ECS
- **KLEAF** — AOSP Clang prebuilt via Bazel + Bazel internal cache

---

## 🙏 Credits

- [ccache-ECS](https://github.com/cctv18/ccache-ECS) — cctv18
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) — ReSukiSU Team
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) — SukiSU Team
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — KernelSU-Next Team
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — simonpunk
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) — osm0sis
- [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) — vc-teahouse
- [BBRv3 backport](https://github.com/WildKernels/kernel_patches/tree/main/common/bbrv3) — fatalcoder524
- [ZeroMount](https://github.com/Enginex0/zeromount) — Enginex0
- [NoMount](https://github.com/maxsteeel/nomount) — maxsteeel
- [Re:Kernel](https://github.com/Sakion-Team/Re-Kernel) — Sakion-Team
- [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) — ravindu644
- [BORE Scheduler](https://github.com/firelzrd/bore-scheduler) — firelzrd
- [ADIOS](https://github.com/firelzrd/adios) — firelzrd
- [NTSync](https://github.com/WildKernels/kernel_patches/tree/main/common/ntsync) — Elizabeth Figura (CodeWeavers)
- [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) — greenforce-project
- [Neutron Clang](https://github.com/Neutron-Toolchains/clang-build-catalogue) — Neutron-Toolchains
- [WeebX Clang](https://github.com/XSans0/WeebX-Clang) — XSans0
- [ZyC Clang](https://github.com/ZyCromerZ/Clang) — ZyCromerZ

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

Feel free to fork and modify — a credit/link back is appreciated
