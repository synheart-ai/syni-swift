# syni-swift

[![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-lightgrey.svg)]()
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

> Source-available · iOS / macOS SDK for [Syni](https://docs.synheart.ai/syni/overview) — adaptive on-device LLM inference with hybrid local/cloud chat, structured persona conditioning, and a streaming chat API designed for the UI thread.

---

## Features

- 🧠 **On-device inference** — Qwen 2 / 2.5 and Gemma 3 GGUF models out of the box; bring your own GGUF for other supported architectures.
- 🌐 **Hybrid local / cloud** — same agent API, choose execution mode per call (`.localFirst`, `.cloudFirst`, `.localOnly`, `.cloudOnly`).
- 🍎 **Apple Foundation Models** — opt-in routing to the on-device system model on supported OS versions; falls back to local GGUF / cloud automatically.
- 🎭 **Versioned personas** — load by id from bundled [syni-spec](https://docs.synheart.ai/syni-spec/overview) JSON; the same id resolves to the same behavior on client and server.
- 🧵 **Actor-isolated** — `async`/`await` throughout; safe from any concurrency context. Streaming via `AsyncThrowingStream<SyniChatEvent, Error>`.
- 🔒 **Verified model downloads** — pinned SHA-256 per model, checked at install time.
- 📡 **Streaming chat** with token-level deltas (`.delta`) plus a final structured response (`.final`).

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/synheart-ai/syni-swift.git", from: "0.0.2"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SyniSwift", package: "syni-swift"),
        ]
    ),
]
```

### Requirements

- iOS 16.0+ / macOS 13.0+
- Swift 5.9+
- Xcode 15+

### Native runtime install

`SyniSwift` is a thin Swift wrapper around the closed-source `syni-runtime`
native core. The runtime is **not** distributed via SwiftPM — install it
once into your project with the `synheart` CLI:

```bash
curl -fsSL https://synheart.sh/install | sh
synheart install runtime syni
```

That writes `SyniRuntime.xcframework` to `<your-project>/synheart/vendor/syni-runtime/`.
Add the framework to your Xcode target under
**General → Frameworks, Libraries, and Embedded Content**.

The SwiftPM package itself has zero binary dependencies — `SyniRuntimeBridge`
resolves all C symbols via `dlsym(RTLD_DEFAULT)` at runtime. You can build
and run tests against the package without the binary; calls into the
runtime fail with a clear error until the install step has been run.

## Usage

Abridged:

```swift
import SyniSwift

@MainActor
final class Demo {
    private let agent = SyniAgent()

    func start() async throws {
        // Load a persona by id from bundled spec assets.
        let persona = try await SyniSpecPersona.load("focus.coach.v1")

        // First-run install: download + verify the model, load the
        // engine, bind the persona. Emits lifecycle events on
        // `agent.installState: AnyPublisher<SyniInstallState, Never>`.
        try await agent.install(
            persona: persona,
            model: SyniModels.qwen25_15bInstructQ4
        )

        // Single-turn chat.
        let response = try await agent.chat("How can I focus right now?")
        print(response.displayText)
    }
}
```

### Streaming

```swift
for try await event in agent.chatStream("hello") {
    switch event {
    case let .delta(text):
        print(text, terminator: "")
    case let .final(response):
        print("\n[\(response.displayText.count) chars]")
    }
}
```

### Hybrid local / cloud

```swift
let agent = SyniAgent(
    cloudConfig: SyniCloudConfig(
        baseUrl: "https://api.synheart.ai",
        authToken: { "<bearer-token>" },
        tenantId: "<tenant>",
        userId: "<user>"
    )
)

let response = try await agent.chat(
    "how was my recent session?",
    mode: .cloudFirst // try cloud, fall back to local
)
```

### Install lifecycle

The `installState` publisher emits the full state machine — wire it into SwiftUI to surface progress:

```swift
@Observable
final class InstallVM {
    var state: SyniInstallState = .notInstalled
    private var cancellable: AnyCancellable?

    func observe(_ agent: SyniAgent) {
        cancellable = agent.installState.sink { [weak self] in self?.state = $0 }
    }
}

// In your view
switch vm.state {
case .notInstalled:
    Button("Install model") { /* trigger install */ }
case let .installing(stage, progress):
    ProgressView("\(stage)", value: progress)
case .installed:
    ChatView()
case let .failed(reason, _):
    Text("Install failed: \(reason)")
}
```

Stages include `.downloadingModel`, `.verifyingModel`, `.loadingEngine`, and `.bindingPersona`.

## Where this fits

`SyniSwift` is the **agent layer** — inference, install lifecycle, persona binding, chat orchestration. It does not own:

- HSI signal collection (the [`SynheartCore`](https://github.com/synheart-ai/synheart-core-swift) SDK does), or
- the four-authority gate (consent + capability + activation + session; also a host concern).

Synheart-ecosystem apps typically depend on `SynheartCore` and use `SyniModule` (which wraps this SDK with those layers). Standalone use of `SyniSwift` is fully supported when you don't need the wider Synheart contract.

## Documentation

- [Syni overview](https://docs.synheart.ai/syni/overview) — Synheart's on-device LLM stack
- [Syni Spec](https://docs.synheart.ai/syni-spec/overview) — canonical persona / safety / schema contracts

## Also available on

| Platform | Package | Repo |
|----------|---------|------|
| Flutter | `syni` (pub.dev) | [syni-flutter](https://github.com/synheart-ai/syni-flutter) |
| Android | `ai.synheart:syni-sdk` (Maven Central) | [syni-kotlin](https://github.com/synheart-ai/syni-kotlin) |

All three SDKs expose the same `SyniAgent` API — same methods, same
states, same persona/model catalog — only the platform idioms differ
(`async`/`AnyPublisher` here, `Future`/`Stream` on Flutter, `suspend`/`Flow`
on Kotlin).

## Contributing

This is a source-available repository. Issues and feature requests are welcome; pull requests are **not accepted** at this time. See [CONTRIBUTING.md](CONTRIBUTING.md) for the rationale and the supported contribution path. Security reports go through [SECURITY.md](SECURITY.md).

## License

[Apache 2.0](LICENSE) © Synheart.
