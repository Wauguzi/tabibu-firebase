package com.tabibukenya.tabibu

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HybridAiContractTest {
    @Test
    fun notesNeverSelectCloud() {
        assertEquals(
            HybridAiPlan.PreferOnDevice,
            HybridAiContract.resolve(HybridAiTask.SymptomTidy, HybridAiContract.preferMode),
        )
        assertEquals(
            HybridAiPlan.PreferOnDevice,
            HybridAiContract.resolve(HybridAiTask.SymptomTidy, null),
        )
        assertEquals(
            HybridAiPlan.OnDeviceOnly,
            HybridAiContract.resolve(HybridAiTask.SymptomTidy, HybridAiContract.onlyMode),
        )
        assertEquals(
            HybridAiPlan.OnDeviceOnly,
            HybridAiContract.resolve(HybridAiTask.NotesSummary, HybridAiContract.preferMode),
        )
        assertEquals(
            HybridAiPlan.OnDeviceOnly,
            HybridAiContract.resolve(HybridAiTask.NotesSummary, HybridAiContract.onlyMode),
        )
        assertEquals(
            HybridAiPlan.OnDeviceOnly,
            HybridAiContract.resolve(HybridAiTask.NotesSummary, null),
        )
        assertEquals(
            HybridAiPlan.OnDeviceOnly,
            HybridAiContract.resolve(HybridAiTask.NotesSummary, "PREFER_IN_CLOUD"),
        )
        assertNull(HybridAiContract.resolve(HybridAiTask.SymptomTidy, "PREFER_IN_CLOUD"))
        assertNull(HybridAiContract.resolve(HybridAiTask.SymptomTidy, 42))
    }

    @Test
    fun onDeviceOnlyNeverReportsCloud() {
        assertEquals(
            "on_device",
            HybridAiContract.resultSource(HybridAiPlan.OnDeviceOnly, onDevice = true),
        )
        assertNull(HybridAiContract.resultSource(HybridAiPlan.OnDeviceOnly, onDevice = false))
        assertEquals(
            "in_cloud",
            HybridAiContract.resultSource(HybridAiPlan.PreferOnDevice, onDevice = false),
        )
    }

    @Test
    fun promptsAreTheVerbatimInstructions() {
        assertFalse(HybridAiContract.tidyInstructions.isEmpty())
        assertFalse(HybridAiContract.summaryInstructions.isEmpty())
        assertTrue(
            HybridAiContract.tidyInstructions.startsWith(
                "Rewrite the patient's symptom note in the same language as the input.",
            ),
        )
        assertTrue(
            HybridAiContract.summaryInstructions.startsWith(
                "Summarise these clinical notes in exactly three short bullet lines",
            ),
        )
        val note = "Call me on 0712345678"
        val turn = HybridAiContract.turn(HybridAiContract.summaryInstructions, note)
        assertTrue(turn.startsWith(HybridAiContract.summaryInstructions))
        assertTrue(turn.endsWith(note))
    }

    @Test
    fun failureCodesStayOffTheMessageBody() {
        assertEquals("network", HybridAiContract.failureCode(IOException("timed out")))
        assertEquals("busy", HybridAiContract.failureCode(IllegalStateException("BUSY")))
        assertEquals("battery", HybridAiContract.failureCode(IllegalStateException("BATTERY")))
        assertEquals(
            "unknown",
            HybridAiContract.failureCode(
                IllegalStateException(
                    "the note itself mentions BUSY and is far longer than eighty characters, so it is left unread",
                ),
            ),
        )
        assertEquals("too_long", HybridAiContract.failureCode(HybridAiCallException("too_long")))
        assertEquals("unavailable", HybridAiContract.statusWire("UNAVAILABLE"))
        assertEquals("downloadable", HybridAiContract.statusWire("DOWNLOADABLE"))
        assertTrue(HybridAiContract.exceedsCap("a".repeat(HybridAiContract.maxInputChars + 1)))
        assertEquals(
            HybridAiContract.defaultCloudModel,
            HybridAiContract.cloudModelName("  "),
        )
        assertEquals(HybridModelOption.Preview, HybridAiContract.modelOption("preview"))
        assertEquals(HybridModelOption.Stable, HybridAiContract.modelOption("nope"))
    }

    @Test
    fun anAnswerCutOffAtTheCapIsRefused() {
        assertTrue(HybridAiContract.cutOff("MAX_TOKENS"))
        assertFalse(HybridAiContract.cutOff("STOP"))
        assertFalse(HybridAiContract.cutOff(null))
    }
}
