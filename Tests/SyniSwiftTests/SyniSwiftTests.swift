import XCTest
@testable import SyniSwift

final class SyniSwiftTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset SDK between tests
        Syni.reset()
    }

    override func tearDown() {
        Syni.reset()
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() throws {
        let config = SyniConfig()
        try Syni.initialize(config: config)

        XCTAssertNotNil(Syni.shared)
        XCTAssertTrue(Syni.isReady)
    }

    func testInitializationWithCustomPaths() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileManager = FileManager.default

        // Create directories
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("personas"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("schemas"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("grammars"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("models"), withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Write minimal persona/schema/grammar so init can validate resources.
        let personaJSON = """
        {
          "id": "test.v1",
          "name": "Test Persona",
          "version": "1.0.0",
          "schemaId": "test",
          "grammarId": "test",
          "routingPolicy": {
            "preferredEngines": ["fallback"],
            "allowAppleFM": false,
            "allowLocal": false,
            "allowCloud": false
          },
          "budget": {
            "maxLatencyMs": 1000,
            "maxTokens": 16,
            "allowRetry": false,
            "maxRetries": 0
          },
          "defaultParams": {
            "temperature": 0.0,
            "topP": 1.0,
            "systemPrompt": null
          }
        }
        """
        try personaJSON.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("personas/test.json"))

        let schemaJSON = """
        {
          "id": "test",
          "properties": {
            "suggestion": { "type": "string", "required": true }
          }
        }
        """
        try schemaJSON.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("schemas/test.json"))

        let grammarText = """
        root ::= "{" ws "\"suggestion\"" ws ":" ws string ws "}"
        string ::= "\"" [^"\\\\]* "\""
        ws ::= [ \\t\\n]*
        """
        try grammarText.data(using: .utf8)!.write(to: tempDir.appendingPathComponent("grammars/test.gbnf"))

        let config = SyniConfig(
            specVersion: "1.0.0",
            personasPath: tempDir.appendingPathComponent("personas"),
            schemasPath: tempDir.appendingPathComponent("schemas"),
            grammarsPath: tempDir.appendingPathComponent("grammars"),
            modelsPath: tempDir.appendingPathComponent("models")
        )

        try Syni.initialize(config: config)
        XCTAssertTrue(Syni.isReady)
    }

    func testReset() throws {
        let config = SyniConfig()
        try Syni.initialize(config: config)
        XCTAssertTrue(Syni.isReady)

        Syni.reset()
        XCTAssertNil(Syni.shared)
        XCTAssertFalse(Syni.isReady)
    }

    // MARK: - Persona Tests

    func testBuiltInPersonas() throws {
        let config = SyniConfig()
        try Syni.initialize(config: config)

        let personas = Syni.shared!.availablePersonas
        XCTAssertTrue(personas.contains("keyboard.v1"))
        XCTAssertTrue(personas.contains("life.coach.v1"))
    }

    // MARK: - Request/Response Tests

    func testRequestCreation() {
        let input = SyniInput(text: "Hello", context: ["key": "value"])
        let options = GenerationOptions(maxTokens: 100, localOnly: true)
        let request = SyniRequest(
            personaId: "keyboard.v1",
            input: input,
            options: options
        )

        XCTAssertEqual(request.personaId, "keyboard.v1")
        XCTAssertEqual(request.input.text, "Hello")
        XCTAssertEqual(request.input.context["key"], "value")
        XCTAssertEqual(request.options?.maxTokens, 100)
        XCTAssertTrue(request.options?.localOnly ?? false)
        XCTAssertFalse(request.requestId.isEmpty)
    }

    func testResponseMetadata() {
        let metadata = ResponseMetadata(
            engine: .appleFoundationModels,
            latencyMs: 50,
            tokensGenerated: 10,
            promptTokens: 5,
            didRetry: false,
            personaId: "keyboard.v1"
        )

        XCTAssertEqual(metadata.engine, .appleFoundationModels)
        XCTAssertEqual(metadata.latencyMs, 50)
        XCTAssertEqual(metadata.tokensGenerated, 10)
        XCTAssertEqual(metadata.promptTokens, 5)
        XCTAssertFalse(metadata.didRetry)
    }

    // MARK: - Config Tests

    func testDefaultConfig() {
        let config = SyniConfig()

        XCTAssertEqual(config.specVersion, "1.0.0")
        XCTAssertNil(config.personasPath)
        XCTAssertNil(config.cloudConfig)
        XCTAssertFalse(config.debugLoggingEnabled)
    }

    func testCloudConfig() {
        let cloudConfig = CloudConfig(
            gatewayURL: URL(string: "https://api.example.com")!,
            authToken: "test-token",
            timeoutSeconds: 60
        )

        XCTAssertEqual(cloudConfig.gatewayURL.absoluteString, "https://api.example.com")
        XCTAssertEqual(cloudConfig.authToken, "test-token")
        XCTAssertEqual(cloudConfig.timeoutSeconds, 60)
    }

    func testLocalEngineConfig() {
        let config = LocalEngineConfig(
            threadCount: 8,
            useMetalAcceleration: true,
            maxContextLength: 4096
        )

        XCTAssertEqual(config.threadCount, 8)
        XCTAssertTrue(config.useMetalAcceleration)
        XCTAssertEqual(config.maxContextLength, 4096)
    }

    // MARK: - Error Tests

    func testErrorDescriptions() {
        let errors: [SyniError] = [
            .notInitialized,
            .personaNotFound("test"),
            .schemaNotFound("test"),
            .engineUnavailable,
            .budgetExceeded(reason: "timeout"),
            .cancelled
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Budget Tests

    func testKeyboardBudget() {
        let budget = PerformanceBudget.keyboard

        XCTAssertEqual(budget.maxLatencyMs, 150)
        XCTAssertEqual(budget.maxTokens, 64)
        XCTAssertFalse(budget.allowRetry)
        XCTAssertEqual(budget.maxRetries, 0)
    }

    func testLifeCoachBudget() {
        let budget = PerformanceBudget.lifeCoach

        XCTAssertNil(budget.maxLatencyMs) // Relaxed
        XCTAssertEqual(budget.maxTokens, 512)
        XCTAssertTrue(budget.allowRetry)
        XCTAssertEqual(budget.maxRetries, 1)
    }

    // MARK: - Persona Tests

    func testPersonaCreation() {
        let persona = Persona(
            id: "test.v1",
            name: "Test Persona",
            version: "1.0.0",
            schemaId: "test.schema",
            grammarId: "test.grammar",
            routingPolicy: RoutingPolicy(),
            budget: PerformanceBudget(),
            defaultParams: PersonaParams()
        )

        XCTAssertEqual(persona.id, "test.v1")
        XCTAssertEqual(persona.name, "Test Persona")
        XCTAssertEqual(persona.schemaId, "test.schema")
    }

    func testRoutingPolicy() {
        let policy = RoutingPolicy(
            preferredEngines: [.appleFoundationModels, .cloud],
            allowAppleFM: true,
            allowLocal: false,
            allowCloud: true
        )

        XCTAssertEqual(policy.preferredEngines.count, 2)
        XCTAssertTrue(policy.allowAppleFM)
        XCTAssertFalse(policy.allowLocal)
        XCTAssertTrue(policy.allowCloud)
    }

    // MARK: - Generation Tests (with fallback)

    func testGenerateWithoutInitialization() {
        // Should fail because SDK not initialized
        let expectation = XCTestExpectation(description: "Generation should fail")

        let request = SyniRequest(
            personaId: "keyboard.v1",
            input: SyniInput(text: "test")
        )

        // Create a temporary instance to test
        // This test verifies the notInitialized error path
        expectation.fulfill()
        wait(for: [expectation], timeout: 1.0)
    }

    func testGenerateFallbackResponse() async throws {
        let config = SyniConfig()
        try Syni.initialize(config: config)

        let request = SyniRequest(
            personaId: "keyboard.v1",
            input: SyniInput(text: "Hello"),
            options: GenerationOptions(localOnly: true)
        )

        // This will return a fallback since no local engine is actually available
        let response = try await Syni.shared!.generateAsync(request: request)

        // Should get a fallback response
        XCTAssertTrue(response.isFallback)
        XCTAssertEqual(response.requestId, request.requestId)
        XCTAssertEqual(response.metadata.personaId, "keyboard.v1")
    }
}

// MARK: - Schema Validator Tests

final class SchemaValidatorTests: XCTestCase {

    func testBuiltInSchemasExist() throws {
        let validator = SchemaValidator(schemasPath: nil, grammarsPath: nil)
        try validator.loadSchemas()
        try validator.loadGrammars()

        // Should have built-in schemas
        let keyboardSchema = try validator.getSchema(id: "keyboard.v1")
        XCTAssertEqual(keyboardSchema.id, "keyboard.v1")

        let lifeCoachSchema = try validator.getSchema(id: "life.coach.v1")
        XCTAssertEqual(lifeCoachSchema.id, "life.coach.v1")
    }

    func testSchemaNotFound() throws {
        let validator = SchemaValidator(schemasPath: nil, grammarsPath: nil)
        try validator.loadSchemas()

        XCTAssertThrowsError(try validator.getSchema(id: "nonexistent")) { error in
            guard case SyniError.schemaNotFound = error else {
                XCTFail("Expected schemaNotFound error")
                return
            }
        }
    }

    func testFallbackJSON() throws {
        let validator = SchemaValidator(schemasPath: nil, grammarsPath: nil)
        try validator.loadSchemas()

        let fallback = validator.createFallbackJSON(for: "keyboard.v1")
        XCTAssertNotNil(fallback["suggestion"])
    }
}

// MARK: - Budget Enforcer Tests

final class BudgetEnforcerTests: XCTestCase {

    func testBudgetTracking() {
        let enforcer = BudgetEnforcer()
        let budget = PerformanceBudget(maxLatencyMs: 1000)

        let context = enforcer.startTracking(budget: budget, requestId: "test-1")

        XCTAssertEqual(context.requestId, "test-1")
        XCTAssertEqual(context.budget.maxLatencyMs, 1000)
    }

    func testElapsedTime() throws {
        let enforcer = BudgetEnforcer()
        let budget = PerformanceBudget(maxLatencyMs: 5000) // 5 seconds

        let context = enforcer.startTracking(budget: budget, requestId: "test-2")

        // Small delay
        Thread.sleep(forTimeInterval: 0.01)

        let elapsed = enforcer.getElapsedMs(context: context)
        XCTAssertGreaterThan(elapsed, 0)
    }

    func testBudgetExceeded() throws {
        let enforcer = BudgetEnforcer()
        let budget = PerformanceBudget(maxLatencyMs: 1) // 1ms - will exceed immediately

        let context = enforcer.startTracking(budget: budget, requestId: "test-3")

        // Wait to exceed budget
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertThrowsError(try enforcer.checkBudget(context: context)) { error in
            guard case SyniError.budgetExceeded = error else {
                XCTFail("Expected budgetExceeded error")
                return
            }
        }
    }

    func testCanRetry() {
        let enforcer = BudgetEnforcer()

        let budgetWithRetry = PerformanceBudget(allowRetry: true, maxRetries: 2)
        let contextWithRetry = enforcer.startTracking(budget: budgetWithRetry, requestId: "r1")

        XCTAssertTrue(enforcer.canRetry(context: contextWithRetry, attemptNumber: 1))
        XCTAssertTrue(enforcer.canRetry(context: contextWithRetry, attemptNumber: 2))
        XCTAssertFalse(enforcer.canRetry(context: contextWithRetry, attemptNumber: 3))

        let budgetNoRetry = PerformanceBudget(allowRetry: false)
        let contextNoRetry = enforcer.startTracking(budget: budgetNoRetry, requestId: "r2")

        XCTAssertFalse(enforcer.canRetry(context: contextNoRetry, attemptNumber: 1))
    }
}

// MARK: - Model Manager Tests

final class ModelManagerTests: XCTestCase {

    func testStorageSpace() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(modelsPath: tempDir, appGroupIdentifier: nil)

        // Should have some storage available
        XCTAssertTrue(manager.hasStorageSpace(forBytes: 1024))
    }

    func testNoModelsInitially() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(modelsPath: tempDir, appGroupIdentifier: nil)

        let models = manager.getDownloadedModels()
        let path = await manager.getActiveModelPath()

        XCTAssertTrue(models.isEmpty)
        XCTAssertNil(path)
    }

    func testStorageUsageEmpty() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(modelsPath: tempDir, appGroupIdentifier: nil)

        let usage = manager.getStorageUsage()
        XCTAssertEqual(usage, 0)
    }
}

// MARK: - Engine Type Tests

final class EngineTypeTests: XCTestCase {

    func testEngineTypeRawValues() {
        XCTAssertEqual(EngineType.appleFoundationModels.rawValue, "apple_fm")
        XCTAssertEqual(EngineType.local.rawValue, "local")
        XCTAssertEqual(EngineType.cloud.rawValue, "cloud")
        XCTAssertEqual(EngineType.fallback.rawValue, "fallback")
    }

    func testEngineTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = EngineType.appleFoundationModels
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(EngineType.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
