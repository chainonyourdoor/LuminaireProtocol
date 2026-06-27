<div align="center">

<img src="https://raw.githubusercontent.com/primer/octicons/main/icons/cpu-24.svg" width="64" height="64" />

# ✨ LuminaireProtocol

**CI/build orchestration for the Luminaire Android GKI kernel**

[![Build](https://img.shields.io/github/actions/workflow/status/chainonyourdoor/LuminaireProtocol/build.yml?branch=main&label=build&logo=github&style=for-the-badge)](https://github.com/chainonyourdoor/LuminaireProtocol/actions/workflows/build.yml)
[![Kernel](https://img.shields.io/badge/kernel-android14--6.1--lts-blue?style=for-the-badge&logo=linux&logoColor=white)](https://github.com/chainonyourdoor/android_kernel_common-6.1)
[![KMI](https://img.shields.io/badge/KMI-gen%2011-purple?style=for-the-badge)](https://source.android.com/docs/core/architecture/kernel/gki-versioning)
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

| Version | Android | Branch | Status |
|---------|---------|--------|--------|
| `6.12` | android16 | `android16-6.12-lts` | ✅ |
| `6.6` | android15 | `android15-6.6-lts` | ✅ |
| `6.1` | android14 | `android14-6.1-lts` | ✅ Currently Active |
| `5.15` | android13 | `android13-5.15-lts` | ✅ |
| `5.10` | android13 | `android13-5.10-lts` | ✅ |

---

## ⚙️ Build Systems

| System | Toolchain | Cache |
|--------|-----------|-------|
| **MAKE** | Greenforce Clang (Cirrus) / Neutron / WeebX / ZyC | ccache-ECS |
| **KLEAF** | AOSP Clang (Bazel prebuilt) | Bazel internal |

---

## 🔑 Root Solutions

| Variant | KSU Fork | SuSFS | Multi-Manager |
|---------|----------|-------|---------------|
| `VANILLA` | ❌ None | ❌ | ❌ |
| `RESUKISU` | ReSukiSU | ✅ | ✅ Dynamic |
| `SUKISU` | SukiSU-Ultra | ❌ | ❌ |

---

## ⚡ Addons

| Addon | Description | Kernel Change |
|-------|-------------|---------------|
| **BBG** | Baseband Guard LSM security module | `security/baseband-guard` |
| **ZeroMount** | VFS path redirection engine | `fs/zeromount.c` |
| **NoMount** | VFS path injection framework | `fs/nomount.c` |
| **Re:Kernel** | Netlink event hook for binder/signal | `drivers/kernelsu` |
| **Droidspaces** | LXC container runtime support | defconfig configs |

---

## 🏗️ Repository Structure

```
LuminaireProtocol/
├── build.sh                  # Main build orchestrator
├── arsenal.sh                # Toolchain & source download orchestrator
├── functions.sh              # Shared helpers (log/warn/error/retry)
│
├── luminaire/
│   ├── setup/                # Deps, ccache, clang setup
│   ├── download/             # Kernel source download (make/kleaf)
│   ├── kernel/
│   │   ├── branding.sh
│   │   ├── config/           # Luminaire config fragment
│   │   ├── android14-6.1-lts/
│   │   │   ├── ksu/          # Root solution scripts
│   │   │   └── patches/      # Version-specific patches
│   │   ├── core/             # Mandatory kernel fixes
│   │   └── addons/           # Optional feature addons
│   ├── build/                # make.sh / kleaf.sh
│   └── release/              # AnyKernel3 packaging + Telegram
│
└── .github/
    ├── workflows/            # CI workflow definitions
    └── actions/              # Reusable composite actions
```

---

## 🙏 Credits

| Project | Author | Role |
|---------|--------|------|
| [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | [ReSukiSU Team](https://github.com/ReSukiSU) | KernelSU fork (RESUKISU variant) |
| [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | [SukiSU Team](https://github.com/SukiSU-Ultra) | KernelSU fork (SUKISU variant) |
| [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) | [simonpunk](https://gitlab.com/simonpunk) | SuSFS kernel patches |
| [AnyKernel3](https://github.com/osm0sis/AnyKernel3) | [osm0sis](https://github.com/osm0sis) | Kernel flasher template |
| [Baseband Guard](https://github.com/vc-teahouse/Baseband-guard) | [vc-teahouse](https://github.com/vc-teahouse) | BBG LSM module |
| [ZeroMount](https://github.com/Enginex0/zeromount) | [Enginex0](https://github.com/Enginex0) | VFS path redirection engine |
| [NoMount](https://github.com/maxsteeel/nomount) | [maxsteeel](https://github.com/maxsteeel) | VFS path injection framework |
| [Re:Kernel](https://github.com/Sakion-Team/Re-Kernel) | [Sakion-Team](https://github.com/Sakion-Team) | Netlink binder/signal hook |
| [Greenforce Clang](https://github.com/greenforce-project/greenforce_clang) | [greenforce-project](https://github.com/greenforce-project) | Cirrus Clang toolchain |
| [Neutron Clang](https://github.com/Neutron-Toolchains/clang-build-catalogue) | [Neutron-Toolchains](https://github.com/Neutron-Toolchains) | Neutron Clang toolchain |
| [WeebX Clang](https://github.com/XSans0/WeebX-Clang) | [XSans0](https://github.com/XSans0) | WeebX Clang toolchain |
| [ZyC Clang](https://github.com/ZyCromerZ/Clang) | [ZyCromerZ](https://github.com/ZyCromerZ) | ZyC Clang toolchain |

---

<div align="center">

Made with ❤️ by [chainonyourdoor](https://github.com/chainonyourdoor)

</div>
