/*
 * Copyright 2026 the DotWel Launcher project contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package app.nothingui.launcher

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetPickerRequestStateTest {

    @Test
    fun coldRequestIsPending() {
        val state = WidgetPickerRequestState()

        assertTrue(state.offer("cold"))
        assertTrue(state.isPending())
        assertEquals("cold", state.pendingId)
    }

    @Test
    fun warmRequestOpensOnce() {
        val state = WidgetPickerRequestState()

        assertTrue(state.offer("warm"))
        assertTrue(state.complete("warm"))
        assertFalse(state.isPending())
        assertFalse(state.complete("warm"))
    }

    @Test
    fun sameIntentCannotReplay() {
        val state = WidgetPickerRequestState()

        state.offer("request")
        state.complete("request")

        assertFalse(state.offer("request"))
        assertFalse(state.isPending())
    }

    @Test
    fun nonNormalTransitionKeepsRequestPending() {
        val state = WidgetPickerRequestState()

        state.offer("transition")
        assertTrue(state.isPending())

        assertTrue(state.complete("transition"))
        assertFalse(state.isPending())
    }

    @Test
    fun realPauseCancelsPending() {
        val state = WidgetPickerRequestState()

        state.offer("paused")
        state.cancel()

        assertFalse(state.isPending())
        assertFalse(state.complete("paused"))
    }

    @Test
    fun requestSurvivesExpectedResumeBeforeCompletion() {
        val state = WidgetPickerRequestState()

        state.offer("expected-resume")
        assertTrue(state.isPending())

        assertTrue(state.complete("expected-resume"))
    }

    @Test
    fun rotationRestoresHandledWithoutReplaying() {
        val state = WidgetPickerRequestState()
        state.offer("rotated")
        state.complete("rotated")

        val recreated = WidgetPickerRequestState()
        recreated.restoreHandled(state.handledId)

        assertFalse(recreated.isPending())
        assertFalse(recreated.offer("rotated"))
    }

    @Test
    fun newerRequestSupersedesStaleCompletion() {
        val state = WidgetPickerRequestState()

        state.offer("first")
        assertTrue(state.offer("second"))
        assertEquals("second", state.pendingId)
        assertFalse(state.complete("first"))
        assertTrue(state.complete("second"))
        assertFalse(state.isPending())
    }

    @Test
    fun newRequestIsNotBlockedByOldHandledFlag() {
        val state = WidgetPickerRequestState()
        state.offer("old")
        state.complete("old")

        assertTrue(state.offer("new"))
        assertTrue(state.isPending())
    }

    @Test
    fun missingIdIsIgnored() {
        val state = WidgetPickerRequestState()

        assertFalse(state.offer(null))
        assertFalse(state.offer(""))
        assertFalse(state.isPending())
        assertNull(state.handledId)
    }
}
