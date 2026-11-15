import FirebaseAILogic
import XCTest

@testable import Runner

/// Unit tests for the hybrid bridge's pure mappings. Anything that touches the
/// model itself (availability on hardware, generation, fallback) is checked by
/// Theo on an Apple Intelligence device; the simulator build proves compilation.
final class HybridAiPluginTests: XCTestCase {
  func testSourceMapping() {
    XCTAssertEqual(
      HybridAiSourceMapper.map(
        modelVersion: HybridAiSourceMapper.systemModelVersion),
      "on_device")
    XCTAssertEqual(
      HybridAiSourceMapper.map(modelVersion: "gemini-3.5-flash-lite"), "in_cloud")
    XCTAssertEqual(
      HybridAiSourceMapper.map(modelVersion: "unknown-model-version"), "in_cloud")
    XCTAssertEqual(HybridAiSourceMapper.map(modelVersion: ""), "in_cloud")
  }

  func testStatusMapping() {
    typealias Availability = FirebaseAI.SystemLanguageModel.Availability
    typealias Reason = FirebaseAI.SystemLanguageModel.Availability.UnavailableReason
    XCTAssertEqual(HybridAiStatus.string(for: .available), "available")
    for reason: Reason in [
      .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unknown,
    ] {
      XCTAssertEqual(
        HybridAiStatus.string(for: .unavailable(reason)), "unavailable",
        "reason \(reason) must report unavailable")
    }
  }

  func testRoutingNeverSendsNotesToCloud() {
    // tidy prefers on-device with cloud fallback; an absent mode defaults there.
    XCTAssertEqual(
      HybridAiPlan.resolve(task: .symptomTidy, modeRaw: HybridAiPlan.preferMode),
      .preferOnDevice)
    XCTAssertEqual(
      HybridAiPlan.resolve(task: .symptomTidy, modeRaw: nil), .preferOnDevice)
    // only-mode stays on-device even for tidy.
    XCTAssertEqual(
      HybridAiPlan.resolve(task: .symptomTidy, modeRaw: HybridAiPlan.onlyMode),
      .onDeviceOnly)
    // summary pins on-device-only no matter what mode arrives (S-5).
    XCTAssertEqual(
      HybridAiPlan.resolve(task: .notesSummary, modeRaw: HybridAiPlan.preferMode),
      .onDeviceOnly)
    XCTAssertEqual(
      HybridAiPlan.resolve(task: .notesSummary, modeRaw: HybridAiPlan.onlyMode),
      .onDeviceOnly)
    XCTAssertEqual(
      HybridAiPlan.resolve(task: .notesSummary, modeRaw: nil), .onDeviceOnly)
    // Unknown modes are rejected, never defaulted to cloud.
    XCTAssertNil(HybridAiPlan.resolve(task: .symptomTidy, modeRaw: "PREFER_IN_CLOUD"))
    XCTAssertNil(HybridAiPlan.resolve(task: .symptomTidy, modeRaw: 42))
  }

  func testPromptsArePresent() {
    // The native side owns both prompts; an empty one must fail loudly here.
    XCTAssertFalse(HybridAiPlugin.tidyInstructions.isEmpty)
    XCTAssertFalse(HybridAiPlugin.summaryInstructions.isEmpty)
  }
}
