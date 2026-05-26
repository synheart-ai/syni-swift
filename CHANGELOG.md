# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.2] - 2026-05-26

### Added

- `SyniAgent.bindPersona(_:)` for cloud-only flows that need a persona
  without a local model.
- `SyniAgent.deleteModel(_:)` returns bytes freed; permanently removes
  the GGUF + sibling `tokenizer.json` from disk (~1.1 GB).
- `SyniAgent.installedBytes(_:)` reports current on-disk usage; pair
  with `deleteModel` to confirm reclaim size before the user accepts.
- `SyniInstaller.deleteModel(_:)` / `installedBytes(_:)` for direct use.

### Changed (BREAKING — pre-1.0, no consumers)

- `SyniCloudConfig.authToken: () async -> String?` replaced with
  `SyniCloudConfig.authHeaders: (String, String) async -> [String: String]`
  — request-aware (HTTP method + URL) so device-attestation auth signed
  over `method + url` (e.g. `X-Synheart-Proof: <jws>`) is expressible.
  Matches `package:syni`'s `authHeaders` callback.
- Native runtime distribution: dropped `Package.swift` `binaryTarget`.
  Consumers install the closed-source `syni-runtime` once with
  `synheart install runtime syni`; the package resolves all C symbols
  at runtime via `dlsym(RTLD_DEFAULT)`. Mirrors `synheart-core-swift`.
- Public API rewritten to match `package:syni` (Flutter) — Kotlin /
  Swift / Flutter SDKs now share one shape.

- Public API rewritten to match `package:syni` (Flutter) — Kotlin / Swift /
  Flutter SDKs now share one shape. App code is structurally identical
  modulo platform idioms (`AsyncSequence` + Combine `AnyPublisher` here,
  `Flow` on Kotlin, `Stream` on Dart).
- `Syni` singleton + `SyniRequest`/`SyniResponse`/`SyniResult` /
  `Persona` / `EngineType` / `Syni.generate` / `Syni.downloadModel` removed
  in favor of:
  - `SyniAgent` (actor; constructed, not a singleton) with `install()`,
    `restoreInstallIfReady()`, `uninstall()`, `chat()`, `chatStream()`,
    `dispose()`, `installState` (Combine `AnyPublisher`), `currentState`,
    `isInstalled`, `hasCloud`.
  - `SyniInstallState` enum (`.notInstalled` / `.installing(stage,progress)`
    / `.installed(personaId,modelPath,runtimeVersion)` /
    `.failed(reason,cause)`) + `SyniInstallStage`.
  - `SyniChatResponse` / `SyniResponseKind` / `SyniChatEvent` enum with
    `.delta(text)` + `.final(response)`.
  - `SyniPersona`, `SyniSpecPersona` (loads bundled
    `personas/prod/<id>.json`), `SyniSpecPersonaError`.
  - `SyniModelSpec`, `SyniModels`, `SyniModelOption` (`.local` /
    `.cloud`), `SyniLocalModel`, `SyniCloudModel`, `SyniModelCatalog`.
  - `SyniCloudConfig`, `SyniCloudException`, `SyniInstallException`.
  - `SyniExecutionMode { localOnly, cloudOnly, localFirst }`.
- In-process router / schema validator / budget enforcer / keyboard
  bridge removed: that logic now lives in the runtime (schema / budget)
  or the host SDK (persona routing).

### Notes

- Local streaming is V1 chunked-from-buffer: `chatStream` emits one delta
  with the full text followed by `.final`. The C ABI exposes
  `syni_engine_run_stream_json` but wiring its `@convention(c)` callback
  through actor boundaries is deferred to a follow-up; the contract holds
  (`delta` then exactly one `.final`) so consumers don't change.
- Cloud streaming is full SSE — content frames arrive as deltas.
