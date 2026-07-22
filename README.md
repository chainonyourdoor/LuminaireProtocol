<div align="center">

<img src="https://raw.githubusercontent.com/primer/octicons/main/icons/cpu-24.svg" width="300" height="300" />


# Luminaire Protocol

[![Build](https://img.shields.io/github/actions/workflow/status/chainonyourdoor/LuminaireProtocol/build.yml?branch=main&label=build&logo=github&style=for-the-badge)](https://github.com/chainonyourdoor/LuminaireProtocol/actions/workflows/build.yml)
[![Telegram](https://img.shields.io/badge/Telegram-Luminaire-blue?style=for-the-badge&logo=telegram)](https://t.me/LuminaireProtocol)
</div>

**Luminaire Protocol** is a build orchestration repository for the **Luminaire** Android GKI kernel.
This repo does **not** contain kernel source — it contains all the scripts and GitHub Actions workflows that:

1. Download the kernel source from `chainonyourdoor/LuminaireKernel-*`
2. Apply patches, integrations, and addons
3. Build the kernel via **MAKE**
4. Package and release via AnyKernel3 and send to Telegram

---
