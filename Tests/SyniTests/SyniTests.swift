import XCTest
@testable import Syni

final class SyniChatResponseTests: XCTestCase {

    func testParsesCoachEnvelope() {
        let raw = """
        {"type":"coach","data":{"message":"breathe","suggestions":[{"text":"in"},{"text":"out"}]}}
        """
        let r = SyniChatResponse.fromRuntimeJson(raw, personaId: "p", runtimeVersion: "v")
        XCTAssertEqual(r.kind, .coach)
        XCTAssertEqual(r.message, "breathe")
        XCTAssertEqual(r.suggestions, ["in", "out"])
        XCTAssertEqual(r.displayText, "breathe")
    }

    func testParsesChatEnvelope() {
        let raw = #"{"type":"chat","data":{"message":"hello"}}"#
        let r = SyniChatResponse.fromRuntimeJson(raw, personaId: "p", runtimeVersion: "v")
        XCTAssertEqual(r.kind, .chat)
        XCTAssertEqual(r.message, "hello")
        XCTAssertTrue(r.suggestions.isEmpty)
    }

    func testParsesSuggestionsEnvelope() {
        let raw = #"{"type":"suggestions","data":{"suggestions":[{"text":"a"},{"text":"b"}]}}"#
        let r = SyniChatResponse.fromRuntimeJson(raw, personaId: "p", runtimeVersion: "v")
        XCTAssertEqual(r.kind, .suggestions)
        XCTAssertNil(r.message)
        XCTAssertEqual(r.suggestions, ["a", "b"])
        XCTAssertEqual(r.displayText, "a")
    }

    func testFallsBackToUnknownOnMalformed() {
        let r = SyniChatResponse.fromRuntimeJson("not json", personaId: "p", runtimeVersion: "v")
        XCTAssertEqual(r.kind, .unknown)
        XCTAssertEqual(r.displayText, "Syni had no response.")
    }

    func testCloudReplyBuildsChatResponse() {
        let r = SyniChatResponse.fromCloudReply("hi there", personaId: "p", runtimeVersion: "cloud")
        XCTAssertEqual(r.kind, .chat)
        XCTAssertEqual(r.message, "hi there")
        XCTAssertEqual(r.displayText, "hi there")
    }
}

final class SyniInstallStateTests: XCTestCase {

    func testInstalledIsInstalled() {
        let s: SyniInstallState = .installed(
            personaId: "p", modelPath: "/tmp/m.gguf", runtimeVersion: "1.2.3"
        )
        XCTAssertTrue(s.isInstalled)
    }

    func testNotInstalledIsNotInstalled() {
        XCTAssertFalse(SyniInstallState.notInstalled.isInstalled)
    }

    func testInstallingProgressRoundtrip() {
        let s: SyniInstallState = .installing(stage: .downloadingModel, progress: 0.42)
        if case let .installing(stage, progress) = s {
            XCTAssertEqual(stage, .downloadingModel)
            XCTAssertEqual(progress, 0.42, accuracy: 0.0001)
        } else { XCTFail("expected .installing") }
    }

    func testFailedCarriesReason() {
        let s: SyniInstallState = .failed(reason: "offline", cause: nil)
        if case let .failed(reason, _) = s {
            XCTAssertEqual(reason, "offline")
        } else { XCTFail("expected .failed") }
    }
}

final class SyniSpecPersonaTests: XCTestCase {

    func testFromJSONMapsRequiredFields() throws {
        let raw = """
        {"id":"focus.coach.v1","name":"Coach","system_prompt":"sp","output_schema_id":"coach.response.v1"}
        """.data(using: .utf8)!
        let p = try SyniSpecPersona.fromJSON(raw)
        XCTAssertEqual(p.id, "focus.coach.v1")
        XCTAssertEqual(p.displayName, "Coach")
        XCTAssertEqual(p.systemPrompt, "sp")
        XCTAssertEqual(p.responseSchemaId, "coach")
    }

    func testFromJSONThrowsOnMissingFields() {
        let raw = #"{"id":"x"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try SyniSpecPersona.fromJSON(raw))
    }

    func testNormalizesSchemaId() {
        XCTAssertEqual(SyniSpecPersona.normalizeOutputSchema("coach.response.v1"), "coach")
        XCTAssertEqual(SyniSpecPersona.normalizeOutputSchema("chat"), "chat")
        XCTAssertEqual(SyniSpecPersona.normalizeOutputSchema("SUGGESTIONS.response.v2"), "suggestions")
    }
}

final class SyniModelCatalogTests: XCTestCase {

    func testBundledContainsLocalAndCloud() {
        let bundled = SyniModelCatalog.bundled
        var hasLocal = false; var hasCloud = false; var hasDefault = false
        for option in bundled {
            switch option {
            case let .local(m):
                hasLocal = true
                if m.isDefault { hasDefault = true }
            case .cloud: hasCloud = true
            }
        }
        XCTAssertTrue(hasLocal)
        XCTAssertTrue(hasCloud)
        XCTAssertTrue(hasDefault)
    }

    func testNoBaseUrlFallsBackToBundled() async {
        let c = SyniModelCatalog(baseUrl: nil)
        let list = await c.available()
        XCTAssertEqual(list.count, SyniModelCatalog.bundled.count)
    }

    func testQwenSpecHasSignedSha256() {
        let spec = SyniModels.qwen25_15bInstructQ4
        XCTAssertEqual(spec.sha256.count, 64)
        XCTAssertTrue(spec.downloadUrl.hasPrefix("https://"))
        XCTAssertTrue(spec.tokenizerUrl.hasPrefix("https://"))
    }
}

final class SyniAgentTests: XCTestCase {

    func testAgentStartsNotInstalled() async {
        let agent = SyniAgent()
        XCTAssertEqual(agent.currentState, .notInstalled)
        XCTAssertFalse(agent.isInstalled)
        XCTAssertFalse(agent.hasCloud)
    }

    func testAgentWithCloudConfigReportsHasCloud() async {
        let cfg = SyniCloudConfig(
            baseUrl: "https://example.invalid",
            authHeaders: { _, _ in [:] },
            tenantId: "t",
            userId: "u"
        )
        let agent = SyniAgent(cloudConfig: cfg)
        XCTAssertTrue(agent.hasCloud)
    }

    func testChatThrowsWhenNotInstalled() async {
        let agent = SyniAgent()
        do {
            _ = try await agent.chat("hi", mode: .localOnly)
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(String(describing: error).contains("not installed"))
        }
    }

    func testCloudOnlyThrowsWithoutConfig() async {
        let agent = SyniAgent()
        // Even before install, this should refuse cloudOnly with no config —
        // but the "not installed" check happens first; that's the contract.
        do {
            _ = try await agent.chat("hi", mode: .cloudOnly)
            XCTFail("expected throw")
        } catch {
            // Acceptable to fail with either "not installed" or "no cloud config"
            // — both are correct refusals.
        }
    }

    func testInstalledBytesIsZeroWhenNothingInstalled() async {
        let agent = SyniAgent()
        let bytes = await agent.installedBytes(SyniModels.qwen25_15bInstructQ4)
        XCTAssertEqual(bytes, 0)
    }

    func testDeleteModelIsNoopWhenNothingInstalled() async throws {
        let agent = SyniAgent()
        let freed = try await agent.deleteModel(SyniModels.qwen25_15bInstructQ4)
        XCTAssertEqual(freed, 0)
        XCTAssertEqual(agent.currentState, .notInstalled)
    }
}
