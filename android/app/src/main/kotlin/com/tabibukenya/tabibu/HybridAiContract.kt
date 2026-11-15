package com.tabibukenya.tabibu

import java.io.IOException

/**
 * Routing, prompts and failure codes for the hybrid bridge.
 *
 * Kept free of the Android and Firebase SDKs so the JVM unit tests can
 * cover the notes-never-reach-the-cloud rule without a device.
 */
internal object HybridAiContract {
    const val channelName = "tabibu/hybrid_ai"
    const val downloadChannelName = "tabibu/hybrid_ai/download"

    /** Agent Platform location. The client Remote Config has no location key. */
    const val cloudLocation = "global"

    /** Used when Dart sends no cloud model. Mirrors `HybridSettings.defaultCloudModel`. */
    const val defaultCloudModel = "gemini-3.5-flash-lite"

    /**
     * Stand-in for the on-device cap of 4,000 tokens, at about four characters
     * a token. Dart refuses longer input first; this is the channel backstop.
     */
    const val maxInputChars = 16_000

    /** On-device output stays under the 256-token guidance. */
    const val maxOutputTokens = 200

    const val preferMode = "PREFER_ON_DEVICE"
    const val onlyMode = "ONLY_ON_DEVICE"

    /**
     * Instructions for `symptom_tidy`. Copied verbatim from the bundle-06 report.
     */
    const val tidyInstructions =
        "Rewrite the patient's symptom note in the same language as the input. " +
            "Keep it short and clear, in the patient's own voice. Do not add facts, " +
            "do not diagnose, do not suggest treatment, do not advise. Output only " +
            "the rewritten note, with no preamble."

    /**
     * Instructions for `notes_summary`. Copied verbatim from the bundle-06 report.
     */
    const val summaryInstructions =
        "Summarise these clinical notes in exactly three short bullet lines, each " +
            "starting with '- '. Use the same language as the notes. State only what " +
            "the notes state; do not diagnose, do not suggest treatment, do not advise."

    fun instructions(task: HybridAiTask): String = when (task) {
        HybridAiTask.SymptomTidy -> tidyInstructions
        HybridAiTask.NotesSummary -> summaryInstructions
    }

    /**
     * The on-device provider in firebase-ai 17.17.0 sends only the prompt text
     * and drops a system instruction, so the instructions lead the prompt.
     * The field text follows, unchanged.
     */
    fun turn(instructions: String, input: String): String = "$instructions\n\n$input"

    fun exceedsCap(input: String): Boolean = input.length > maxInputChars

    fun cloudModelName(raw: Any?): String {
        val text = (raw as? String)?.trim()
        return if (text.isNullOrEmpty()) defaultCloudModel else text
    }

    fun modelOption(raw: Any?): HybridModelOption =
        if (raw == "preview") HybridModelOption.Preview else HybridModelOption.Stable

    /**
     * `notes_summary` is on-device whatever [modeRaw] is, including a missing
     * or prefer-cloud mode: those notes can identify the patient (S-5).
     * A missing tidy mode defaults to prefer-on-device. Any other tidy mode
     * is rejected so it cannot fall through to the cloud.
     */
    fun resolve(task: HybridAiTask, modeRaw: Any?): HybridAiPlan? {
        if (task == HybridAiTask.NotesSummary) return HybridAiPlan.OnDeviceOnly
        if (modeRaw == null) return HybridAiPlan.PreferOnDevice
        val mode = modeRaw as? String ?: return null
        return when (mode) {
            preferMode -> HybridAiPlan.PreferOnDevice
            onlyMode -> HybridAiPlan.OnDeviceOnly
            else -> null
        }
    }

    /**
     * Wire source for a plan. An on-device-only plan that did not run on
     * device fails closed (null) rather than reporting `in_cloud`.
     */
    fun resultSource(plan: HybridAiPlan, onDevice: Boolean): String? = when (plan) {
        HybridAiPlan.OnDeviceOnly -> if (onDevice) "on_device" else null
        HybridAiPlan.PreferOnDevice -> if (onDevice) "on_device" else "in_cloud"
    }

    /** `OnDeviceModelStatus.toString()` is the token (`AVAILABLE`, …). */
    fun statusWire(token: String): String = when (token) {
        "AVAILABLE" -> "available"
        "DOWNLOADABLE" -> "downloadable"
        "DOWNLOADING" -> "downloading"
        else -> "unavailable"
    }

    /**
     * Dart failure code. The message is never logged: it can echo the prompt.
     * Short SDK tokens (`BUSY`, battery) are recognised; a long message is not
     * inspected, so field text cannot decide the code.
     */
    fun failureCode(error: Throwable): String {
        var current: Throwable? = error
        while (current != null) {
            if (current is HybridAiCallException) return current.code
            when (current.javaClass.simpleName) {
                "FirebaseAIOnDeviceNotAvailableException",
                "ServiceDisabledException",
                -> return "unavailable"
                "QuotaExceededException" -> return "battery"
                "RequestTimeoutException",
                "ServiceConnectionHandshakeFailedException",
                -> return "network"
                "SessionAlreadyReceivingException" -> return "busy"
            }
            if (current is IOException) return "network"
            val message = current.message
            if (
                current is IllegalStateException &&
                message != null &&
                message.contains("FirebaseApp")
            ) {
                return "unavailable"
            }
            if (message != null && message.length <= 80) {
                if (busyToken.containsMatchIn(message)) return "busy"
                if (batteryToken.containsMatchIn(message)) return "battery"
            }
            current = current.cause
        }
        return "unknown"
    }

    private val busyToken = Regex("""\bBUSY\b""")
    private val batteryToken = Regex("""\b(BATTERY|LOW_POWER)\b""", RegexOption.IGNORE_CASE)
}

internal enum class HybridAiTask {
    SymptomTidy,
    NotesSummary,
    ;

    val wire: String
        get() = when (this) {
            SymptomTidy -> "symptom_tidy"
            NotesSummary -> "notes_summary"
        }

    companion object {
        fun fromWire(raw: Any?): HybridAiTask? = when (raw) {
            "symptom_tidy" -> SymptomTidy
            "notes_summary" -> NotesSummary
            else -> null
        }
    }
}

/** `OnDeviceOnly` never builds a cloud model. */
internal enum class HybridAiPlan {
    OnDeviceOnly,
    PreferOnDevice,
}

internal enum class HybridModelOption {
    Stable,
    Preview,
}

/** A failure we raised. [code] is the Dart `PlatformException` code. */
internal class HybridAiCallException(val code: String) : Exception(code)
