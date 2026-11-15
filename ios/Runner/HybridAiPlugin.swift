import FirebaseAILogic
import Flutter
import UIKit
import os

/// Native side of `MethodChannel("tabibu/hybrid_ai")` (Dart: `HybridAiService`).
///
/// iOS implements `status`, `download` and `generate`; anything else answers
/// not-implemented. There is no event channel: Apple owns the on-device model
/// download and the app cannot trigger or observe it.
///
/// Contract (pinned here; the Dart side defines the same keys):
/// - `status` → `"available"` | `"unavailable"` (bare string).
/// - `download` → always throws `"unavailable"`: no app-triggered download exists.
/// - `generate` takes `{task, input, mode, modelOption, cloudModel}` and returns
///   `{text, source}` with `source` one of `"on_device"` | `"in_cloud"`.
/// - `task` is `symptom_tidy` or `notes_summary`; `mode` is `PREFER_ON_DEVICE`
///   or `ONLY_ON_DEVICE`. `modelOption` is accepted and ignored (Apple selects
///   the model). A missing `mode` defaults per task; anything else malformed
///   throws `"invalid_args"`.
/// - `notes_summary` and `ONLY_ON_DEVICE` never touch the cloud (S-5): the
///   notes may identify the patient and only the server de-identifies.
/// - Failures throw the Dart failure codes: `unavailable`, `busy`, `network`,
///   `too_long`, `unknown`. `battery` and `not_english` are never emitted here.
///
/// The prompts live below as constants and are quoted verbatim in the bundle-06
/// report so Android carries the same words. Nothing logged here ever includes
/// prompt or input text.
final class HybridAiPlugin: NSObject, FlutterPlugin {
  static let channelName = "tabibu/hybrid_ai"

  /// Agent Platform location for the cloud leg. The app's client Remote Config
  /// carries no location (`ai_location` is a server-template param), so this is
  /// the documented default, shared with the server.
  static let cloudLocation = "global"

  /// Cloud model when Dart sends none. Mirrors `HybridSettings.defaultCloudModel`.
  static let defaultCloudModel = "gemini-3.5-flash-lite"

  /// Mirrors Dart's `hybridMaxInputChars`: ~4,000 tokens at ~4 UTF-16 units each.
  /// Dart refuses longer input first; this is the channel-side backstop.
  static let maxInputUtf16Units = 16_000

  /// Instructions for `symptom_tidy`: rewrite the patient's own words.
  static let tidyInstructions = "Rewrite the patient's symptom note in the same " +
    "language as the input. Keep it short and clear, in the patient's own voice. " +
    "Do not add facts, do not diagnose, do not suggest treatment, do not advise. " +
    "Output only the rewritten note, with no preamble."

  /// Instructions for `notes_summary`: three bullets for the doctor's quick check.
  static let summaryInstructions = "Summarise these clinical notes in exactly three " +
    "short bullet lines, each starting with '- '. Use the same language as the notes. " +
    "State only what the notes state; do not diagnose, do not suggest treatment, " +
    "do not advise."

  private static let log = Logger(
    subsystem: "com.tabibukenya.tabibu", category: "hybrid-ai")

  private lazy var firebaseAI = FirebaseAI.firebaseAI(
    backend: .vertexAI(location: Self.cloudLocation))

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(HybridAiPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(HybridAiStatus.current())
    case "download":
      // No app-triggered download on iOS; the OS owns the model.
      result(FlutterError(
        code: "unavailable", message: "download not supported", details: nil))
    case "generate":
      handleGenerate(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Generate

  private func handleGenerate(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
          let task = HybridAiTask(rawValue: args["task"] as? String ?? ""),
          let input = args["input"] as? String,
          !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let plan = HybridAiPlan.resolve(task: task, modeRaw: args["mode"])
    else {
      result(FlutterError(code: "invalid_args", message: "malformed generate call",
                          details: nil))
      return
    }
    guard input.utf16.count <= Self.maxInputUtf16Units else {
      result(FlutterError(code: "too_long", message: "input too long", details: nil))
      return
    }
    let cloudModel = nonempty(args["cloudModel"] as? String) ?? Self.defaultCloudModel
    Task {
      let output = await generate(task: task, input: input, plan: plan,
                                  cloudModel: cloudModel)
      await MainActor.run { result(output) }
    }
  }

  private func generate(task: HybridAiTask, input: String, plan: HybridAiPlan,
                        cloudModel: String) async -> Any {
    let inBackground = await MainActor.run {
      UIApplication.shared.applicationState == .background
    }
    guard !inBackground else {
      // On-device inference is foreground-only; fail rather than half-run.
      return FlutterError(code: "unavailable", message: "background", details: nil)
    }
    do {
      switch plan {
      case .onDeviceOnly:
        return try await respondOnDevice(input: input, instructions: task.instructions)
      case .preferOnDevice:
        return try await respondPreferringOnDevice(
          input: input, instructions: task.instructions, cloudModel: cloudModel)
      }
    } catch let failure as HybridAiFailure {
      Self.log.error("generate failed: \(failure.code, privacy: .public)")
      return FlutterError(code: failure.code, message: failure.code, details: nil)
    } catch {
      Self.log.error("generate failed: unknown")
      return FlutterError(code: "unknown", message: "unknown", details: nil)
    }
  }

  /// System model only; used for `notes_summary` and `ONLY_ON_DEVICE`.
  /// Never constructs a cloud model, so no failure path can leak to the cloud.
  private func respondOnDevice(input: String, instructions: String) async throws -> Any {
    guard #available(iOS 26.0, *),
          FirebaseAI.SystemLanguageModel.default.isAvailable
    else {
      throw HybridAiFailure.unavailable
    }
    let session = firebaseAI.generativeModelSession(
      model: FirebaseAI.SystemLanguageModel.default, instructions: instructions)
    let text = try await respondText(session: session, input: input)
    // Structurally on-device: no cloud leg exists on this path.
    return ["text": text, "source": HybridAiSource.onDevice]
  }

  /// System model first with cloud fallback; used for `symptom_tidy`.
  private func respondPreferringOnDevice(input: String, instructions: String,
                                         cloudModel: String) async throws -> Any {
    if #available(iOS 26.0, *) {
      let hybrid = HybridModel(
        primary: FirebaseAI.SystemLanguageModel.default,
        secondary: firebaseAI.geminiModel(name: cloudModel))
      let session = firebaseAI.generativeModelSession(
        model: hybrid, instructions: instructions)
      let response = try await respondFull(session: session, input: input)
      return [
        "text": response.text,
        "source": HybridAiSourceMapper.map(modelVersion: response.modelVersion),
      ]
    } else {
      // Older iOS has no on-device model: tidy goes straight to the cloud.
      return try await respondCloud(input: input, instructions: instructions,
                                    cloudModel: cloudModel)
    }
  }

  private func respondCloud(input: String, instructions: String,
                            cloudModel: String) async throws -> Any {
    let session = firebaseAI.generativeModelSession(
      model: firebaseAI.geminiModel(name: cloudModel), instructions: instructions)
    let text = try await respondText(session: session, input: input)
    return ["text": text, "source": HybridAiSource.inCloud]
  }

  private func respondText(session: GenerativeModelSession, input: String) async throws -> String {
    let response = try await respondFull(session: session, input: input)
    return response.text
  }

  private func respondFull(session: GenerativeModelSession, input: String) async throws
    -> (text: String, modelVersion: String)
  {
    let response: GenerativeModelSession.Response<String>
    do {
      response = try await session.respond(to: input)
    } catch {
      throw HybridAiFailureMapper.map(error)
    }
    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      // An empty answer is a failure, never a blank proposal.
      throw HybridAiFailure.unknown
    }
    return (text: response.content, modelVersion: response.rawResponse.modelVersion)
  }
}

// MARK: - Tasks, plans, sources

// Internal (not private) so RunnerTests covers the routing matrix.
enum HybridAiTask: String {
  case symptomTidy = "symptom_tidy"
  case notesSummary = "notes_summary"

  var instructions: String {
    switch self {
    case .symptomTidy: return HybridAiPlugin.tidyInstructions
    case .notesSummary: return HybridAiPlugin.summaryInstructions
    }
  }
}

/// Routing resolved per request. `notes_summary` pins on-device-only no matter
/// what mode arrives, so a miscoded caller can never send notes to the cloud.
enum HybridAiPlan: Equatable {
  case onDeviceOnly
  case preferOnDevice

  static let preferMode = "PREFER_ON_DEVICE"
  static let onlyMode = "ONLY_ON_DEVICE"

  /// The plan for a task and mode, or nil when the mode is unknown.
  /// A missing mode defaults per task.
  static func resolve(task: HybridAiTask, modeRaw: Any?) -> HybridAiPlan? {
    if task == .notesSummary {
      return .onDeviceOnly
    }
    if modeRaw == nil || modeRaw is NSNull {
      return .preferOnDevice
    }
    guard let mode = modeRaw as? String else {
      return nil
    }
    switch mode {
    case preferMode: return .preferOnDevice
    case onlyMode: return .onDeviceOnly
    default: return nil
    }
  }
}

private enum HybridAiSource {
  static let onDevice = "on_device"
  static let inCloud = "in_cloud"
}

/// Maps `rawResponse.modelVersion` to the wire source. Only the exact system
/// model name counts as on-device; anything else came down the network path.
enum HybridAiSourceMapper {
  static let systemModelVersion = "apple-foundation-models-system-language-model"

  static func map(modelVersion: String) -> String {
    modelVersion == systemModelVersion ? HybridAiSource.onDevice : HybridAiSource.inCloud
  }
}

// MARK: - Status

enum HybridAiStatus {
  /// Bare wire string: the Dart contract has no reason channel.
  static func current() -> String {
    if #available(iOS 26.0, *) {
      return string(for: FirebaseAI.SystemLanguageModel.default.availability)
    }
    return "unavailable"
  }

  static func string(
    for availability: FirebaseAI.SystemLanguageModel.Availability) -> String
  {
    switch availability {
    case .available:
      return "available"
    case .unavailable:
      return "unavailable"
    }
  }
}

// MARK: - Failures

private enum HybridAiFailure: Error {
  case unavailable
  case busy
  case network
  case unknown

  var code: String {
    switch self {
    case .unavailable: return "unavailable"
    case .busy: return "busy"
    case .network: return "network"
    case .unknown: return "unknown"
    }
  }
}

private enum HybridAiFailureMapper {
  static func map(_ error: Error) -> HybridAiFailure {
    if let generation = error as? GenerativeModelSession.GenerationError {
      switch generation {
      case .concurrentRequests:
        return .busy
      case .internalError(_, let underlying):
        return isNetwork(underlying) ? .network : .unknown
      default:
        return .unknown
      }
    }
    return isNetwork(error) ? .network : .unknown
  }

  private static func isNetwork(_ error: Error) -> Bool {
    if error is URLError {
      return true
    }
    return (error as NSError).domain == NSURLErrorDomain
  }
}

private func nonempty(_ raw: String?) -> String? {
  guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
        !trimmed.isEmpty
  else {
    return nil
  }
  return trimmed
}
