# LuminaireProtocol — CODEX

Semua alasan teknis, histori bug-fix, dan konteks non-obvious yang tadinya
tersebar sebagai comment di 72+ script, dikumpulin di sini. Script sendiri
sekarang cuma isinya logic + shebang + (khusus addon/root-solution/luminaire
feature) header banner repo — biar gampang dibaca alurnya tanpa keganggu
paragraf penjelasan. Kalau ada baris kode yang keliatan aneh/gak jelas
kenapa, cari di sini duluan sebelum "nyederhanain" nya.

Terorganisir per-path, sesuai struktur folder repo.

## Daftar Isi

- [build.sh](#buildsh)
- [functions.sh](#functionssh)
- [kernel/checkpoint/scout.sh](#kernelcheckpointscoutsh)
- [kernel/checkpoint/engine.sh](#kernelcheckpointenginesh)

---

## `build.sh`

**`exec 2>&1`** (baris awal) — GitHub Actions nangkep stdout dan stderr
sebagai 2 stream buffer terpisah dan gak jamin urutan relatifnya pas
di-render di log. `log()`/`warn()`/`error()` nulis ke stderr sementara
`::group::`/`::endgroup::` nulis ke stdout — tanpa ini, baris log bisa
kerender di luar blok `::group::` tempat dia sebenernya ditulis. Nge-merge
stderr ke stdout di sini bikin semuanya satu stream, jaga urutan tulis
yang beneran.

**`DRY_RUN`** — skip compile beneran (lihat `build/make.sh`) biar sisa
pipeline bisa dites cepet abis refactor. Di-derive di `build.yml` dari
`RUN_MODE=="Dry Run"`, jadi gak akan pernah gak sinkron sama `RUN_MODE`
pas nyampe sini.

**Registry sourcing di atas (`kernel/{addons,luminaire,ksu-shared}/registry.sh`)**
— didefinisiin `run_addons()`/`run_luminaire()` (plus map version-support
masing-masing) di sini, bukan di dalem `main()`, biar jadi function call
biasa aja di `main()` kayak yang lain, dan `build.sh` gak perlu tau
kebijakan addon/luminaire apapun.

**`wait_for_apt` di `main()`** — nunggu background `apt install` (mulai di
`01_deps.sh`) kelar — `02_ccache.sh` (cmake/ninja/g++) dan `build/make.sh`
(bc/bison/flex) butuh package ini udah ada sebelum jalan. `arsenal.sh`
udah lakuin ini dari awal; `build.sh` dulu enggak, yang bisa race di
runner baru.

**`run_variant()`** — root solution yang gak disupport itu BUKAN skip
opsional (beda sama addon) — label rilis (`Ak3-*-${KERNEL_VARIANT}-*.zip`)
itu identity-critical, jadi ngirim vanilla dengan label KSUNEXT/dll gara2
variant-nya gak disupport buat kernel version ini itu lebih parah
ketimbang build-nya gagal total secara eksplisit.

**`run_core()`** — daftar script eksplisit (bukan glob semua `.sh` di
folder) biar gak accidental ke-source file temp/gak-relevan.

**Kenapa `run_luminaire()`/`run_addons()` gak didefinisiin di `build.sh`**
— keduanya (plus map version-support & conflict matrix addon) tinggal di
`kernel/luminaire/registry.sh` dan `kernel/addons/registry.sh`, di-source
deket atas file ini. Sengaja dikeluarin dari `build.sh` biar file ini
tetep jadi orchestrator (nentuin KAPAN sesuatu jalan) bukan juga megang
APA yang disupport.

**`run_postbuild()`** — sengaja dipisah dari `run_addons()`/`run_build()`:
addon di `run_addons()` nge-patch source/defconfig dan ke-compile bareng
1 build vmlinux di `run_build()`. Sebagian addon butuh kerjaan SETELAH
`run_build()` kelar — misal LKM out-of-tree Kasumi butuh `Module.symvers`
dari kernel tree yang baru dibuild, yang belum ada sebelum titik itu.

Ini thin dispatcher, bentuknya sama kayak `run_build()`: gak tau/peduli
addon tertentu postbuild-nya ngapain (compile LKM, atau apapun addon
masa depan butuhin) — cuma jalanin `kernel/addons/<nama>/postbuild.sh`
buat tiap addon yang ke-*apply*. Gate-nya pake membership di
`$APPLIED_ADDONS` (list hasil filter-versi dari `run_addons()`), BUKAN
`$ADDONS` mentah — addon yang di-skip di situ (versi kernel gak disupport)
gak pernah kejalanin script utamanya, jadi state yang harusnya
di-export (misal `$KASUMI_SRC_DIR` punya Kasumi) juga gak pernah ada.
Kalau gate-nya pake `$ADDONS` mentah, bakal tetep nyoba jalanin
`postbuild.sh`-nya dan gagal gara-gara state yang hilang itu. Addon tanpa
`postbuild.sh` (mayoritas — yang cuma patch/Kconfig doang) otomatis
ke-skip di sini, gak butuh flag "enabled" terpisah.


## `functions.sh`

**`run_quiet()`** — capture exit code `$?` dilakuin di baris sendiri
persis setelah command jalan, bukan lewat `if cmd; then ...; fi` tanpa
`else`. Alasannya: bash me-reset `$?` jadi 0 buat konstruksi itu kalau
kondisinya false — itu diem-diem ngubah setiap command failure jadi
"false success". Pola yang sama dipakai lagi di `retry()`.

**`mark_stage_ok()`** — dipanggil tepat setelah tiap stage `build.sh`
selesai (lihat `main()`). Berkat `set -e`, stage yang gagal bakal exit
duluan sebelum sempet manggil `mark_stage_ok`-nya sendiri — jadi
`kernel/checkpoint/engine.sh` bisa tau stage mana yang gagal cuma dari
ngecek marker mana yang berhasil masuk ke env job itu. Ini yang bikin
`engine.sh` gak salah nyalahin kandidat KSU-fork/SuSFS buat kegagalan
yang sebenernya kejadian di stage lain (misal `run_addons`, atau
`run_postbuild` — addon kayak Kasumi yang gagal di kompilasi LKM
post-build-nya) padahal bukan di `run_variant`/`run_build` (tempat
kandidat itu beneran dipakai). No-op di luar CI (`GITHUB_ENV` unset), jadi
aman dipanggil dari run manual/lokal `build.sh` juga.

**`write_dry_run_image()`** — dipakai `build/make.sh` pas `DRY_RUN=true`
(cuma di-set `build.yml` kalau `RUN_MODE="Dry Run"`). Nulis file placeholder
di path yang harusnya ditempatin kernel Image beneran, biar packaging step
`release/anykernel.sh` (dan semua yang di-hilirnya — notif Telegram,
checkpoint promotion) bisa dites tanpa beneran compile.

**`resolve_android_version()`** — mapping `KERNEL_VERSION` (misal "6.1") ke
prefix branch `ANDROID_VERSION`-nya (misal "android14"). Dipakai bareng
`build.sh` dan `arsenal.sh`, jadi tabel versi cuma perlu diupdate di 1
tempat pas nambah kernel version baru.

**`run_setup()`** — source semua `*.sh` di `setup/`, berurutan. Dipakai
bareng `build.sh` dan `arsenal.sh`.

**`run_step()`** — bentuk generik dari pola "cek file ada -> `::group::` ->
source -> `::endgroup::`" yang dipakai berulang di dispatch step satu-file
`build.sh` (`restore_kernel_source`, 2 pemanggilan di `run_variant`,
`run_build`, `run_release`). Args: `<emoji> <label buat ::group:: dan error>
<path script> <pesan error kalau script hilang>`.

**`wait_for_apt()`** — nunggu background `apt install` yang di-trigger
`setup/01_deps.sh` (`APT_PID`). Dipakai bareng `build.sh` dan `arsenal.sh`
biar runner baru gak lanjut ke step ccache/build sebelum package yang
dibutuhin kepasang. Poll dibatasi 10 menit (bukan `wait` polos yang gak ada
timeout-nya) — pernah kejadian di Setup Arsenal run #430, stuck 17+ menit
tanpa sinyal apa-apa. 10 menit itu udah lebih dari cukup buat install
package list ini dari cold-cache berkali-kali; lewat dari itu, emang ada
yang beneran salah.

**`retry()`** — retry command dengan exponential backoff. Usage:
`retry <max_attempts> <command...>`. Capture `$?` pake pola yang sama kayak
`run_quiet()` (baris sendiri, bukan lewat `if cmd; then...; fi` tanpa
`else`).

**`cache_freshness_note()`** — note buat log restore cache clang/kernel-
source/AK3, jelasin KENAPA cache itu dipulihin (bukan cuma "berhasil
dipulihin"). `Start-Build` selalu restore (`USE_*_CACHE` hardcoded "true"
di situ) — `Prepare Arsenal` adalah satu-satunya titik yang nentuin apakah
cache bareng ini beneran fresh di run ini (`CACHE_REFRESHED`, dari input
'Update Arsenal'). Tanpa ini, "restored from cache ✅" kebacanya sama aja
antara cache baru banget vs udah berminggu-minggu — misleading kalau
dibaca dari log 1 job doang.

**`mode_emoji()`** — lookup emoji per `RUN_MODE`, dipakai di banner
buka/tutup `build.sh`. Sengaja dipisah jadi lookup (bukan nempelin emoji
langsung ke `RUN_MODE`), karena `RUN_MODE` di-exact-string-compare di
tempat lain (`scout.sh`, `telegram.sh`, dan `build.sh` sendiri lewat
`"${RUN_MODE^^}" = "WARM RUN"`) — kalau value-nya diutak-atik di sini,
diem-diem bakal ngerusak perbandingan itu.

---

## `kernel/checkpoint/scout.sh`

**Tujuan file ini**: nentuin git ref (commit SHA) yang harus dipakai tiap
komponen upstream yang ditrack (ReSukiSU, SukiSU-Ultra, SuSFS) buat build
kali ini.

- `RUN_MODE=Release`: selalu pakai pin known-good dari manifest. Gak pernah
  query upstream, gak pernah build kandidat yang belum ke-test.
- `RUN_MODE=Build/Warm Run`: query commit terbaru upstream. Kalau beda
  dari pin dan belum known-bad, itu jadi kandidat buat run ini —
  `kernel/checkpoint/engine.sh` yang mutusin abis build apakah mau
  di-promote atau di-blacklist.
- **Exception (deadlock-breaking retest)**: kalau belum ada pin good sama
  sekali DAN commit terbaru upstream udah keblacklist, gak ada ref
  known-good buat fallback. Fallback ke ref kosong bakal bikin build
  script diem-diem default clone HEAD branch upstream (SHA yang sama
  yang keblacklist tadi) tanpa pernah dicatet sebagai kandidat — deadlock
  permanen di mana Release mode gak akan pernah lolos berapa kalipun Warm
  Run/Build sukses. Di kasus spesifik ini doang, ref yang keblacklist
  dicoba lagi sebagai kandidat last-resort biar hasil build beneran bisa
  promote atau re-blacklist dia.

Export (via `$GITHUB_ENV`) buat tiap komponen relevan:
`<COMPONENT>_REF` (SHA yang beneran dipakai buat build), `CANDIDATE_<COMPONENT>`
("true" kalau REF itu kandidat belum terverifikasi).

**Manifest belum ada** (`kernel/<ver>/manifest.json` gak ketemu) — itu cuma
berarti belum pernah ada pin yang di-promote buat versi ini, normal buat
kernel version yang belum ada histori checkpoint, bukan misconfiguration.
Fallback ke object kosong `{}` biar default `// ""` / `// []` di
`resolve_component` tetep jalan sama kayak kalau key fork-nya emang gak
ada di manifest yang udah ada.

**`latest_sha_or_empty()`** — gak pernah nge-gagalin build; masalah lookup
cuma berarti "gak ada kandidat run ini, pakai pin". `GH_API_AUTH` itu PAT
GitHub — cuma dilampirin buat call ke `api.github.com`. Ngirim ke target
non-GitHub kayak `gitlab.com` (misal lookup SuSFS) itu header
Authorization asing/invalid dari sudut pandang GitLab, yang bakal ditolak
cepet (~300ms, konsisten tiap run — bukan profile timeout/rate-limit).
Nge-scope header ke target aslinya nyegah ini; logging `http_code`/
`curl_exit` di bawahnya ngasih bukti konkret kalau lookup gagal lagi nanti.

**`resolve_component()`** — resolve 1 komponen: bandingin latest upstream
vs pin + bad-list, export `<COMPONENT>_REF` / `CANDIDATE_<COMPONENT>` ke
`$GITHUB_ENV`. Kasus deadlock (`is_bad=true` dan `good` kosong): tanpa
branch ini, `ref` bakal fallback ke `$good` kosong selamanya — build
script di hilir diem-diem default clone HEAD branch upstream (persis SHA
"bad" ini), tapi karena `candidate` tetep "false" di sini, `engine.sh` gak
pernah dapet kesempatan promote itu meskipun build-nya sukses. Efeknya:
Release mode gak akan pernah lolos buat komponen ini, seberapa banyakpun
Warm Run/Build hijau kejadian (konfirmasi kejadian nyata di
SUKISU+SUSFS: `sukisu_builtin` stuck di `b88403d2561b` sejak keblacklist
run 28687541974; branch builtin upstream emang gak gerak sejak itu).
Fix-nya: coba lagi sebagai kandidat last-resort — sukses berarti promote &
deadlock kebuka; gagal ya cuma re-blacklist SHA yang sama (`engine.sh`'s
`bad |= (. + [...]) | unique` bikin itu no-op), jadi gak bisa lebih parah
dari state permanent-failure yang digantiinnya.

**`RESUKISU`** case: SuSFS pairing pakai `simonpunk/susfs4ksu` branch
`gki-<android_ver>-<kernel_ver>` langsung.

**`SUKISU`** case, SuSFS enabled: branch `"builtin"` itu line SUSFS-
terintegrasi punya SukiSU-Ultra sendiri — dipelihara aktif sama tim
SukiSU-Ultra biar tetep sinkron sama SuSFS, beda sama `"main"` yang udah
pindah ke arsitektur (`syscall_hook_manager`) yang gak compatible sama
adapter patch SuSFS sama sekali. Jadi buat kasus SUSFS, track tip branch
ini langsung, bukan pasangan pin hasil kurasi manual — model yang sama
kayak tracking ReSukiSU. SukiSU-Ultra non-SUSFS: `setup.sh` upstream-nya
sendiri default ke *tag* terbaru (bukan HEAD `main`) kalau gak dikasih
ref — disamain semantiknya di sini.

**`KSUNEXT`** case, SuSFS enabled: SuSFS source buat pairing ini dari
`simonpunk/susfs4ksu` resmi (sama kayak ReSukiSU/SukiSU-Ultra di atas),
BUKAN dari fork susfs4ksu-nya pershoot. Diverifikasi langsung ke source:
fork KernelSU-Next dev-susfs-nya pershoot cuma manggil simbol `susfs_*`
yang udah disediain `susfs4ksu` official-nya simonpunk
(`susfs_is_current_proc_umounted`/`susfs_set_current_proc_umounted`
sebagai `static inline` di `susfs_def.h`, struct
`st_susfs_uname`/`st_susfs_avc_log_spoofing` di `susfs.h`, dll) —
tambahan SELinux/hook milik pershoot sendiri (`kernel/selinux/`,
`kernel/hook/`) itu self-contained, gak butuh apa-apa tambahan dari
susfs4ksu. `susfs_def.h` byte-identical di branch `gki-android14-6.1-dev`,
`gki-android13-5.15-dev`, dan `gki-android12-5.10-dev` milik simonpunk,
jadi ini kerja sama persis buat semua kernel version — gak perlu
pembatasan per-versi di sini. KernelSU-Next non-SUSFS: `setup.sh`
upstream-nya sendiri default ke *tag* terbaru kalau gak dikasih ref (sama
semantiknya kayak branch non-SUSFS SukiSU-Ultra) — disamain di sini juga.

---

## `kernel/checkpoint/engine.sh`

**Tujuan file ini**: jalan setelah build step (selalu, bahkan pas gagal).

- Kandidat sukses → promote: `manifest`'s `"good"` jadi SHA ini.
- Kandidat gagal → blacklist: append ke `"bad"`, `"good"` gak disentuh
  (ini SENDIRI rollback-nya — gak ada yang lain berubah).
- Gak ada kandidat dipake run ini → gak ngapa-ngapain.

Matrix job (RESUKISU/SUKISU) jalan paralel dan bisa aja bareng-bareng
nulis `manifest.json`, jadi tiap write lewat retry loop fetch-rebase-push,
bukan commit+push sekali doang.

Args: `<build outcome: "success" | "failure"> <component key dipisah spasi
buat dicek, misal "resukisu susfs">`

**Kenapa `REMOTE` di-construct manual pake `PERSONAL_TOKEN`** — masalah
push 403 `github-actions[bot]` itu udah difix di step checkout
`Start-Build` punya `build.yml` (`persist-credentials: false`), BUKAN di
sini. `actions/checkout` v6+ persist auth header yang di-inject-nya lewat
config global `includeIf.gitdir` yang nunjuk ke file di bawah
`$RUNNER_TEMP`, bukan `.git/config` lokal repo ini — jadi unset
`http.https://github.com/.extraheader` di sini gak ngefek apa-apa; fix-nya
emang harus di step checkout itu sendiri (liat changelog/issue tracker
`actions/checkout` v6, PR "Persist creds to a separate file").

**`apply_and_push()`** — apply 1 patch jq ke `manifest.json` di atas
`main` terbaru, push, retry kalau ada fast-forward conflict dari matrix
job lain yang jalan bareng.

- `git reset -q --hard FETCH_HEAD` setelah fetch: HARUS beneran mindahin
  HEAD lokal ke `FETCH_HEAD` sebelum commit — `git fetch` doang gak
  lakuin itu. Tanpa baris ini, tiap retry commit ulang di atas parent basi
  yang sama, jadi conflict beneran (push dari matrix job lain yang
  konkuren) gagal identik tiap attempt dan loop ini gak akan pernah
  beneran recover (confirmed pake repro 2-clone beneran sebelum fix ini
  landing: 0/5 attempt sukses tanpa baris ini, 1/1 dengan baris ini).
  `workspace/` di-gitignore, jadi ini gak nyentuh kernel source tree yang
  lagi in-progress.
- Checkpoint write pertama kali buat kernel version ini: file (dan
  foldernya) belum ada di repo. Itu normal, bukan error — bootstrap object
  kosong biar jq ada yang di-patch.
- jq yang gagal di sini dulu diem-diem ketelan: `mv` gak pernah jalan,
  `manifest.json` gak berubah, git nemuin "nothing to commit", dan
  `apply_and_push` return 0 seakan-akan update-nya beneran kejadian —
  confirmed beneran kejadian di jalur promote (error `.bad -= [...]` pas
  `.bad` null/hilang, yang kena di tiap `manifest.json` abis fresh-reset).
  Sekarang gagal loud biar `jq_patch` yang rusak gak pernah kekira no-op
  yang legitimate.

**`file_issue()`** — buka (atau biarin kebuka) GitHub Issue buat komponen
upstream yang rusak, di-dedup pake title yang stabil biar retest yang
berulang-ulang gagal gak nge-spam. `gh issue create` gagal total (gak ada
issue sama sekali) kalau label-nya belum ada di repo — jadi dibikin dulu
idempotently.

**Loop utama, per komponen, kasus failure** — `build.sh`'s `main()` cuma
nge-set marker ini lewat `mark_stage_ok()` (lihat `functions.sh`) setelah
stage terkait beneran selesai — `set -e` bikin stage yang gagal gak
pernah nyampe ke marker-nya sendiri, jadi keberadaan marker itu ngasih
tau stage mana yang gagal tanpa `engine.sh` perlu tau state internal
`build.sh` apapun.

- `CHECKPOINT_VARIANT_OK` hilang → gagal di/sebelum `run_variant`, persis
  di situ candidate ref ini di-apply → salahin.
- `CHECKPOINT_VARIANT_OK` ada tapi `CHECKPOINT_ADDONS_OK` hilang → gagal
  di `run_core` atau `run_addons`, dua-duanya gak ada hubungannya sama
  kandidat KSU-fork/SuSFS yang ditrack komponen ini → biarin pin-nya.
- `CHECKPOINT_ADDONS_OK` ada tapi `CHECKPOINT_BUILD_OK` hilang → gagal di
  `run_build` sendiri (compile beneran), yang patch kandidatnya emang bisa
  jadi penyebabnya → salahin, sama kayak kasus gagal di stage
  `run_variant`.
- `CHECKPOINT_BUILD_OK` ada → `run_build` udah selesai, jadi kegagalannya
  kejadian di `run_postbuild` (misal compile LKM out-of-tree Kasumi) — gak
  ada hubungannya sama kandidat KSU-fork/SuSFS, yang cuma pernah dipake di
  `run_variant`/`run_build` → biarin pin-nya. Ini dulu ke-anggep sama kayak
  kasus `run_build` di atas (gak ada marker antara keduanya), yang salah
  nge-blacklist kandidat `susfs_resukisu`/`susfs_sukisu` `be08face56c3`
  buat kernel 5.10 gara-gara kegagalan post-build Kasumi yang gak ada
  hubungannya — lihat histori `manifest.json`.
