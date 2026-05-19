/**
 * Syni Runtime - C API
 *
 * A cross-platform LLM inference engine with compatible interface.
 * Supports iOS, macOS, Android, Windows, Linux via FFI.
 */

#ifndef SYNI_C_API_H
#define SYNI_C_API_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#define SYNI_EXPORT EMSCRIPTEN_KEEPALIVE
#else
#define SYNI_EXPORT
#endif

#if defined(_WIN32)
#define SYNI_API __declspec(dllexport)
#else
#define SYNI_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Types
// ============================================================================

/** Opaque engine handle. */
typedef struct syni_engine_t syni_engine_t;

/** Preset enum for different use cases. */
typedef enum syni_preset_t {
    SYNI_PRESET_KEYBOARD = 0,  /**< Fast keyboard suggestions (150ms, 64 tokens) */
    SYNI_PRESET_COACH = 1,     /**< Coach responses (2000ms, 256 tokens) */
    SYNI_PRESET_CHAT = 2,      /**< General chat (5000ms, 512 tokens) */
} syni_preset_t;

/**
 * Inference request structure.
 *
 * This mirrors the API for familiarity and easy migration.
 */
typedef struct syni_inference_request_t {
    int32_t request_id;              /**< Unique ID for tracking/cancellation */
    int32_t context_size;            /**< Context window size in tokens */
    const char* input;               /**< Input prompt (UTF-8) */
    int32_t max_tokens;              /**< Maximum tokens to generate */
    const char* model_path;          /**< Path to GGUF model file */
    int32_t num_gpu_layers;          /**< GPU layers (0=CPU, 99=all GPU) */
    int32_t num_threads;             /**< CPU threads (default: 4) */
    float temperature;               /**< Sampling temperature (default: 0.7) */
    float top_p;                     /**< Top-p sampling (default: 0.9) */
    float penalty_freq;              /**< Frequency penalty (0-1) */
    float penalty_repeat;            /**< Repeat penalty (0-1) */
    uint64_t seed;                   /**< Random seed for reproducibility */
    const char* grammar;             /**< Optional BNF grammar for structured output */
    const char* eos_token;           /**< Optional EOS token override */
    void (*logger)(const char*);     /**< Optional log callback */
    const char* openai_request_json; /**< Optional OpenAI-format JSON request */
} syni_inference_request_t;

/**
 * Callback for streaming inference results.
 *
 * @param response Current accumulated response text (UTF-8)
 * @param json_response OpenAI-compatible JSON response
 * @param done 1 if generation complete, 0 otherwise
 */
typedef void (*syni_inference_callback_t)(
    const char* response,
    const char* json_response,
    uint8_t done
);

/**
 * Callback for streaming chunks with user data.
 *
 * @param chunk Current token/chunk (UTF-8)
 * @param user_data User-provided context
 * @return false to stop streaming, true to continue
 */
typedef bool (*syni_stream_callback_t)(
    const char* chunk,
    void* user_data
);

/**
 * Log callback type.
 */
typedef void (*syni_log_callback_t)(const char* message);

// ============================================================================
// Engine Lifecycle
// ============================================================================

/**
 * Create a new engine instance.
 *
 * @return Engine handle, or NULL on failure
 */
SYNI_API SYNI_EXPORT
syni_engine_t* syni_engine_new(void);

/**
 * Create engine with a default model path.
 *
 * @param model_path Path to GGUF model file
 * @return Engine handle, or NULL on failure
 */
SYNI_API SYNI_EXPORT
syni_engine_t* syni_engine_new_with_model(const char* model_path);

/**
 * Load a model into an existing engine.
 *
 * Call this before inference if you used syni_engine_new() without a model.
 *
 * @param engine Engine handle
 * @param model_path Path to GGUF model file
 * @return true on success, false on failure
 */
SYNI_API SYNI_EXPORT
bool syni_engine_load_model(syni_engine_t* engine, const char* model_path);

/**
 * Free an engine instance.
 *
 * @param engine Engine handle (NULL-safe)
 */
SYNI_API SYNI_EXPORT
void syni_engine_free(syni_engine_t* engine);

/**
 * Free a string returned by any syni_* function.
 *
 * @param s String pointer (NULL-safe)
 */
SYNI_API SYNI_EXPORT
void syni_string_free(char* s);

// ============================================================================
// Synchronous Inference (Simple JSON API)
// ============================================================================

/**
 * Run synchronous inference with JSON input/output.
 *
 * @param engine Engine handle
 * @param preset Performance preset
 * @param seed Random seed
 * @param request_json JSON request matching EngineRequest schema
 * @return JSON response (caller must free with syni_string_free), NULL on error
 */
SYNI_API SYNI_EXPORT
char* syni_engine_run_json(
    syni_engine_t* engine,
    syni_preset_t preset,
    uint64_t seed,
    const char* request_json
);

/**
 * Run streaming inference with JSON input.
 *
 * @param engine Engine handle
 * @param preset Performance preset
 * @param seed Random seed
 * @param request_json JSON request
 * @param cb Streaming callback (called for each chunk)
 * @param user_data User context passed to callback
 * @return Final JSON response (caller must free), NULL on error
 */
SYNI_API SYNI_EXPORT
char* syni_engine_run_stream_json(
    syni_engine_t* engine,
    syni_preset_t preset,
    uint64_t seed,
    const char* request_json,
    syni_stream_callback_t cb,
    void* user_data
);

// ============================================================================
// Async Inference
// ============================================================================

/**
 * Enqueue an async inference request.
 *
 * This is the compatible async API. The callback is invoked
 * when generation completes or fails.
 *
 * @param engine Engine handle
 * @param request Inference request parameters
 * @param callback Completion callback
 * @return Request ID for cancellation, or 0 on error
 */
SYNI_API SYNI_EXPORT
uint64_t syni_inference_async(
    syni_engine_t* engine,
    const syni_inference_request_t* request,
    syni_inference_callback_t callback
);

/**
 * Run synchronous inference with request struct.
 *
 * Blocks until completion. Callback is invoked with results.
 *
 * @param engine Engine handle
 * @param request Inference request parameters
 * @param callback Completion callback
 */
SYNI_API SYNI_EXPORT
void syni_inference_sync(
    syni_engine_t* engine,
    const syni_inference_request_t* request,
    syni_inference_callback_t callback
);

/**
 * Cancel an in-flight inference request.
 *
 * @param engine Engine handle
 * @param request_id ID returned by syni_inference_async
 * @return true if cancellation was signaled, false if request not found
 */
SYNI_API SYNI_EXPORT
bool syni_inference_cancel(syni_engine_t* engine, uint64_t request_id);

// ============================================================================
// Tokenization
// ============================================================================

/**
 * Tokenize text and return token IDs.
 *
 * @param engine Engine handle
 * @param model_path Path to model (for vocabulary)
 * @param text Text to tokenize (UTF-8)
 * @return JSON object with "tokens" array and "count" (caller must free)
 */
SYNI_API SYNI_EXPORT
char* syni_tokenize(
    syni_engine_t* engine,
    const char* model_path,
    const char* text
);

/**
 * Count tokens in text (faster than full tokenization).
 *
 * @param engine Engine handle
 * @param model_path Path to model
 * @param text Text to count
 * @return Token count, or -1 on error
 */
SYNI_API SYNI_EXPORT
int32_t syni_token_count(
    syni_engine_t* engine,
    const char* model_path,
    const char* text
);

// ============================================================================
// Model Metadata
// ============================================================================

/**
 * Get chat template from model (if embedded in GGUF).
 *
 * @param engine Engine handle
 * @param model_path Path to model
 * @return Chat template string (caller must free), empty if not present
 */
SYNI_API SYNI_EXPORT
char* syni_chat_template_get(syni_engine_t* engine, const char* model_path);

/**
 * Get EOS token from model.
 *
 * @param engine Engine handle
 * @param model_path Path to model
 * @return EOS token string (caller must free)
 */
SYNI_API SYNI_EXPORT
char* syni_eos_token_get(syni_engine_t* engine, const char* model_path);

/**
 * Get BOS token from model.
 *
 * @param engine Engine handle
 * @param model_path Path to model
 * @return BOS token string (caller must free)
 */
SYNI_API SYNI_EXPORT
char* syni_bos_token_get(syni_engine_t* engine, const char* model_path);

// ============================================================================
// Health & Diagnostics
// ============================================================================

/**
 * Health check.
 *
 * @param engine Engine handle
 * @return 0 on success, non-zero on error
 */
SYNI_API SYNI_EXPORT
int32_t syni_engine_healthcheck(syni_engine_t* engine);

/**
 * Get telemetry snapshot as JSON.
 *
 * @param engine Engine handle
 * @return JSON array of inference metrics (caller must free)
 */
SYNI_API SYNI_EXPORT
char* syni_telemetry_json(syni_engine_t* engine);

/**
 * Get number of pending requests in queue.
 *
 * @param engine Engine handle
 * @return Pending count, or -1 on error
 */
SYNI_API SYNI_EXPORT
int32_t syni_queue_pending_count(syni_engine_t* engine);

/**
 * Get number of cached models.
 *
 * @param engine Engine handle
 * @return Cache count, or -1 on error
 */
SYNI_API SYNI_EXPORT
int32_t syni_model_cache_count(syni_engine_t* engine);

/**
 * Clear the model cache.
 *
 * @param engine Engine handle
 */
SYNI_API SYNI_EXPORT
void syni_model_cache_clear(syni_engine_t* engine);

// ============================================================================
// Version
// ============================================================================

/**
 * Get library version string.
 *
 * @return Version string (caller must free)
 */
SYNI_API SYNI_EXPORT
char* syni_version(void);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // SYNI_C_API_H
