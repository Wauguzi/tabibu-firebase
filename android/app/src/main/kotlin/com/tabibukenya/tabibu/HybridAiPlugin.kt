@file:OptIn(PublicPreviewAPI::class)

package com.tabibukenya.tabibu

import android.util.Log
import androidx.lifecycle.Lifecycle
import com.google.firebase.Firebase
import com.google.firebase.ai.FirebaseAI
import com.google.firebase.ai.GenerativeModel
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.InferenceSource
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.OnDeviceExtension
import com.google.firebase.ai.OnDeviceModelOption
import com.google.firebase.ai.ai
import com.google.firebase.ai.DownloadStatus
import com.google.firebase.ai.type.GenerationConfig
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.PublicPreviewAPI
import com.google.firebase.ai.type.content
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Native side of `MethodChannel("tabibu/hybrid_ai")`.
 *
 * Uses the default [Firebase] app and the App Check provider FlutterFire
 * already installed. Firebase is not initialised here.
 *
 * `notes_summary` and `ONLY_ON_DEVICE` use [InferenceMode.ONLY_ON_DEVICE],
 * whose builder constructs only the on-device provider. Contact details are
 * already removed in `HybridRequest.toMap` for a tidy, so they are not
 * stripped again here.
 *
 * Nothing logged from this class includes the prompt or the field text.
 */
class HybridAiPlugin(
    private val activity: FlutterFragmentActivity,
) : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var downloadJob: kotlinx.coroutines.Job? = null
    private val models = HashMap<String, GenerativeModel>()

    private val firebaseAi: FirebaseAI by lazy {
        // agentPlatform is the non-deprecated name on firebase-ai 17.17.0.
        // vertexAI still exists and defaults to us-central1; it is not called.
        Firebase.ai(backend = GenerativeBackend.agentPlatform(HybridAiContract.cloudLocation))
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, HybridAiContract.channelName).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, HybridAiContract.downloadChannelName).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope.cancel()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        events = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
        downloadJob?.cancel()
        downloadJob = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> launch(result) { status() }
            "download" -> launch(result) {
                startDownload()
                null
            }
            "warmUp" -> launch(result) {
                warmUp()
                null
            }
            "generate" -> launch(result) { generate(call.arguments) }
            else -> result.notImplemented()
        }
    }

    private fun launch(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                val value = block()
                reply(result) { result.success(value) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                val code = HybridAiContract.failureCode(error)
                Log.i(tag, "call failed: $code")
                reply(result) { result.error(code, code, null) }
            }
        }
    }

    private suspend fun status(): String {
        return try {
            val extension = requireOnDevice()
            HybridAiContract.statusWire(extension.checkStatus().toString())
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Throwable) {
            Log.i(tag, "status failed: ${HybridAiContract.failureCode(error)}")
            "unavailable"
        }
    }

    /**
     * Starts a download only because Dart called `download`. Status and
     * generate never collect the download flow, so a model is not fetched
     * on mobile data in the background.
     */
    private suspend fun startDownload() {
        ensureForeground()
        if (downloadJob?.isActive == true) throw HybridAiCallException("busy")
        val extension = requireOnDevice()
        downloadJob = scope.launch {
            try {
                var total = 0L
                extension.download().collect { update ->
                    when (update) {
                        is DownloadStatus.DownloadStarted -> {
                            total = update.bytesToDownload
                            emitProgress(0.0)
                        }
                        is DownloadStatus.DownloadInProgress -> {
                            val fraction = if (total > 0L) {
                                update.totalBytesDownloaded.toDouble() / total.toDouble()
                            } else {
                                0.0
                            }
                            emitProgress(fraction.coerceIn(0.0, 1.0))
                        }
                        is DownloadStatus.DownloadCompleted -> emitProgress(1.0)
                        is DownloadStatus.DownloadFailed -> {
                            val code = HybridAiContract.failureCode(update.exception)
                            Log.i(tag, "download failed: $code")
                            emitError(code)
                        }
                        else -> emitError("unknown")
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                val code = HybridAiContract.failureCode(error)
                Log.i(tag, "download failed: $code")
                emitError(code)
            }
        }
    }

    private suspend fun warmUp() {
        ensureForeground()
        requireOnDevice().warmUp()
    }

    private suspend fun generate(arguments: Any?): Map<String, String> {
        val args = arguments as? Map<*, *> ?: throw HybridAiCallException("invalid_args")
        val task = HybridAiTask.fromWire(args["task"])
        val input = args["input"] as? String
        val plan = task?.let { HybridAiContract.resolve(it, args["mode"]) }
        if (task == null || input == null || input.trim().isEmpty() || plan == null) {
            throw HybridAiCallException("invalid_args")
        }
        if (HybridAiContract.exceedsCap(input)) throw HybridAiCallException("too_long")
        ensureForeground()
        val option = HybridAiContract.modelOption(args["modelOption"])
        // The caller's cloud model is not read on the on-device-only path.
        val cloudModel = if (plan == HybridAiPlan.PreferOnDevice) {
            HybridAiContract.cloudModelName(args["cloudModel"])
        } else {
            HybridAiContract.defaultCloudModel
        }
        val model = model(task, plan, option, cloudModel)
        val response = model.generateContent(
            HybridAiContract.turn(HybridAiContract.instructions(task), input),
        )
        val text = response.text?.trim().orEmpty()
        if (text.isEmpty()) throw HybridAiCallException("unknown")
        val onDevice = response.inferenceSource == InferenceSource.ON_DEVICE
        val source = HybridAiContract.resultSource(plan, onDevice)
            ?: throw HybridAiCallException("unknown")
        return mapOf("text" to text, "source" to source)
    }

    private fun model(
        task: HybridAiTask,
        plan: HybridAiPlan,
        option: HybridModelOption,
        cloudModel: String,
    ): GenerativeModel {
        val key = "${task.wire}|${plan.name}|${option.name}|$cloudModel"
        return models.getOrPut(key) {
            val onDeviceOnly = plan == HybridAiPlan.OnDeviceOnly
            firebaseAi.generativeModel(
                // The SDK requires a model name even for ONLY_ON_DEVICE. That
                // mode's builder never calls the cloud provider.
                modelName = cloudModel,
                generationConfig = if (onDeviceOnly) {
                    null
                } else {
                    GenerationConfig.builder()
                        .setMaxOutputTokens(HybridAiContract.maxOutputTokens)
                        .build()
                },
                systemInstruction = content(role = "system") {
                    text(HybridAiContract.instructions(task))
                },
                onDeviceConfig = OnDeviceConfig(
                    mode = if (onDeviceOnly) {
                        InferenceMode.ONLY_ON_DEVICE
                    } else {
                        InferenceMode.PREFER_ON_DEVICE
                    },
                    maxOutputTokens = HybridAiContract.maxOutputTokens,
                    modelOption = when (option) {
                        HybridModelOption.Preview -> OnDeviceModelOption.PREVIEW
                        HybridModelOption.Stable -> OnDeviceModelOption.STABLE
                    },
                ),
            )
        }
    }

    /** Status, download and warm-up follow the stable on-device model. */
    private fun requireOnDevice(): OnDeviceExtension {
        val key = "status|stable"
        val model = models.getOrPut(key) {
            firebaseAi.generativeModel(
                modelName = HybridAiContract.defaultCloudModel,
                onDeviceConfig = OnDeviceConfig(
                    mode = InferenceMode.ONLY_ON_DEVICE,
                    modelOption = OnDeviceModelOption.STABLE,
                ),
            )
        }
        return model.onDeviceExtension ?: throw HybridAiCallException("unavailable")
    }

    private fun ensureForeground() {
        // On-device inference is foreground-only. A stopped activity is backgrounded.
        if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
            throw HybridAiCallException("unavailable")
        }
    }

    private fun emitProgress(value: Double) {
        try {
            events?.success(value)
        } catch (error: IllegalStateException) {
            Log.i(tag, "progress dropped: ${HybridAiContract.failureCode(error)}")
        }
    }

    private fun emitError(code: String) {
        try {
            events?.error(code, code, null)
        } catch (error: IllegalStateException) {
            Log.i(tag, "progress dropped: ${HybridAiContract.failureCode(error)}")
        }
    }

    private fun reply(result: MethodChannel.Result, send: () -> Unit) {
        try {
            send()
        } catch (error: IllegalStateException) {
            Log.i(tag, "reply dropped: ${HybridAiContract.failureCode(error)}")
        }
    }

    companion object {
        private const val tag = "hybrid-ai"

        fun register(engine: FlutterEngine, activity: FlutterFragmentActivity) {
            engine.plugins.add(HybridAiPlugin(activity))
        }
    }
}
