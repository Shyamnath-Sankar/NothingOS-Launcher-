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

package app.nothingui.weather

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WeatherSettingsControllerTest {

    private val oldKey = "51.5074,-0.1278"
    private val newKey = "48.8566,2.3522"

    @Test
    fun theInitialStateIsDisabledBlankAndCannotEnable() {
        val controller = controller()

        val state = controller.state.value

        assertFalse(state.saved.enabled)
        assertEquals("", state.draft.label)
        assertEquals("", state.draft.latitudeText)
        assertEquals("", state.draft.longitudeText)
        assertFalse(state.draft.consentChecked)
        assertFalse(state.canEnable)
        assertTrue(controller.store.writes.isEmpty())
    }

    @Test
    fun typingValidFieldsAndTickingConsentNeverEnablesByItself() = runBlocking {
        val controller = controller()

        controller.onDraftChanged(validDraft())

        assertFalse(controller.state.value.saved.enabled)
        assertFalse(controller.state.value.isEnabled)
        assertTrue(controller.store.writes.isEmpty())
        assertTrue(controller.observed.isEmpty())
    }

    @Test
    fun enableRequiresTheExplicitConsentCheckbox() = runBlocking {
        val controller = controller()
        controller.onDraftChanged(validDraft(consentChecked = false))

        controller.enable()

        assertEquals(WeatherSettingsMessage.CONSENT_REQUIRED, controller.state.value.message)
        assertFalse(controller.state.value.saved.enabled)
        assertTrue(controller.store.writes.isEmpty())
    }

    @Test
    fun enableRejectsAnInvalidLocation() = runBlocking {
        val controller = controller()
        controller.onDraftChanged(validDraft(latitudeText = "999"))

        controller.enable()

        assertEquals(WeatherSettingsMessage.INVALID_LOCATION, controller.state.value.message)
        assertFalse(controller.state.value.saved.enabled)
        assertTrue(controller.store.writes.isEmpty())
    }

    @Test
    fun enableWritesOneNormalizedConsentAndTellsTheSessionGate() = runBlocking {
        val controller = controller()
        controller.onDraftChanged(
            validDraft(
                label = "  Home   window ",
                latitudeText = "51.50744999",
                longitudeText = "-0.12784999",
            ),
        )

        controller.enable()

        val state = controller.state.value
        assertTrue(state.saved.enabled)
        assertEquals("Home window", state.saved.location!!.label)
        assertEquals(oldKey, state.saved.location.cacheKey)
        assertEquals(WeatherSettingsMessage.ENABLED, state.message)
        assertEquals(1, controller.store.writes.size)
        assertTrue(controller.store.state.enabled)
        assertEquals(state.saved, controller.observed.last())
        assertFalse(state.draft.consentChecked)
    }

    @Test
    fun editingAnEnabledLocationRevokesOldConsentAndClearsItsCacheBeforeReEnable() = runBlocking {
        val controller = controller()
        enable(controller)
        val oldGeneration = controller.store.state.generation

        controller.onDraftChanged(validDraft(label = "Work", latitudeText = "48.8566", longitudeText = "2.3522"))

        val revoked = controller.state.value
        assertFalse(revoked.saved.enabled)
        assertNull(revoked.saved.location)
        assertTrue(revoked.saved.generation > oldGeneration)
        assertEquals(WeatherSettingsMessage.REVOKED_BY_EDIT, revoked.message)
        assertEquals(listOf(oldKey), controller.cache.clearedKeys)
        assertFalse(controller.observed.last().enabled)
        assertEquals("Work", revoked.draft.label)
        assertFalse(revoked.draft.consentChecked)
        assertFalse(revoked.canEnable)

        controller.onDraftChanged(revoked.draft.copy(consentChecked = true))
        controller.enable()

        val enabled = controller.state.value
        assertTrue(enabled.saved.enabled)
        assertEquals(newKey, enabled.saved.location!!.cacheKey)
        assertEquals(newKey, controller.store.state.location!!.cacheKey)
        assertEquals(WeatherSettingsMessage.ENABLED, enabled.message)
    }

    @Test
    fun disableClearsThePersistedLocationAndStopsTheSessionImmediately() = runBlocking {
        val controller = controller()
        enable(controller)

        controller.disable()

        val state = controller.state.value
        assertFalse(state.saved.enabled)
        assertNull(state.saved.location)
        assertEquals("", state.draft.label)
        assertEquals("", state.draft.latitudeText)
        assertEquals("", state.draft.longitudeText)
        assertEquals(listOf(oldKey), controller.cache.clearedKeys)
        assertFalse(controller.observed.last().enabled)
        assertEquals(WeatherSettingsMessage.DISABLED, state.message)
        assertEquals(2, controller.store.writes.size)
    }

    @Test
    fun aStaleEnableCannotResurrectConsentAfterAnotherWriterDisabledIt() = runBlocking {
        val controller = controller()
        controller.onDraftChanged(validDraft())
        controller.store.state = WeatherConsentPolicy.disable(WeatherConsentState.DISABLED)

        controller.enable()

        assertFalse(controller.state.value.saved.enabled)
        assertEquals(WeatherSettingsMessage.CONFLICT, controller.state.value.message)
        assertFalse(controller.store.state.enabled)
        assertTrue(controller.observed.isEmpty())
    }

    @Test
    fun aStorageFailureNeverClaimsThatConsentWasEnabled() = runBlocking {
        val controller = controller()
        controller.store.failNextWrite = true
        controller.onDraftChanged(validDraft())

        controller.enable()

        assertFalse(controller.state.value.saved.enabled)
        assertEquals(WeatherSettingsMessage.STORAGE_FAILURE, controller.state.value.message)
        assertFalse(controller.store.state.enabled)
        assertTrue(controller.observed.isEmpty())
    }

    @Test
    fun aDisableRetryWinsOverAStaleEnableFromAnotherWriter() = runBlocking {
        val controller = controller()
        enable(controller)
        val stale = controller.state.value.saved
        controller.store.state = WeatherConsentPolicy.enable(controller.store.state, location(newKey))

        controller.disable()

        assertFalse(controller.state.value.saved.enabled)
        assertFalse(controller.store.state.enabled)
        assertNull(controller.store.state.location)
        assertTrue(controller.observed.last().enabled.not())
        assertTrue(controller.state.value.saved.generation > stale.generation)
    }

    @Test
    fun aRecreatedControllerRestoresEnabledEvidenceOnlyAfterARealCommit() = runBlocking {
        val store = FakeConsentStore()
        val first = controller(store = store)
        enable(first)

        val recreated = controller(store = store)

        assertTrue(recreated.state.value.saved.enabled)
        assertEquals(oldKey, recreated.state.value.saved.location!!.cacheKey)
        assertEquals("Home", recreated.state.value.draft.label)
        assertEquals("51.5074", recreated.state.value.draft.latitudeText)
        assertEquals("-0.1278", recreated.state.value.draft.longitudeText)
        assertFalse(recreated.state.value.draft.consentChecked)
    }

    @Test
    fun aRecreatedControllerAfterDisableStaysDisabledAndBlank() = runBlocking {
        val store = FakeConsentStore()
        val first = controller(store = store)
        enable(first)
        first.disable()

        val recreated = controller(store = store)

        assertFalse(recreated.state.value.saved.enabled)
        assertNull(recreated.state.value.saved.location)
        assertEquals("", recreated.state.value.draft.label)
        assertFalse(recreated.state.value.canEnable)
    }

    private fun controller(store: FakeConsentStore = FakeConsentStore()): ControllerHarness {
        val harness = ControllerHarness(store)
        return harness
    }

    private suspend fun enable(controller: ControllerHarness) {
        controller.onDraftChanged(validDraft())
        controller.enable()
        assertTrue(controller.state.value.saved.enabled)
    }

    private fun validDraft(
        label: String = "Home",
        latitudeText: String = "51.5074",
        longitudeText: String = "-0.1278",
        consentChecked: Boolean = true,
    ): WeatherSettingsDraft = WeatherSettingsDraft(
        label = label,
        latitudeText = latitudeText,
        longitudeText = longitudeText,
        consentChecked = consentChecked,
    )

    private fun location(key: String): WeatherManualLocation {
        val (latitude, longitude) = key.split(',')
        return (
            WeatherConsentPolicy.parseLocation("Other", latitude, longitude)
                as WeatherLocationInput.Valid
            ).location
    }

    private inner class ControllerHarness(
        val store: FakeConsentStore,
    ) {
        val cache = RecordingCacheStore()
        val observed = mutableListOf<WeatherConsentState>()
        val controller = WeatherSettingsController(
            store = store,
            cacheStore = cache,
            consentObserver = { observed += it },
            ioDispatcher = Dispatchers.Unconfined,
        )

        val state get() = controller.state

        suspend fun onDraftChanged(draft: WeatherSettingsDraft) = controller.onDraftChanged(draft)

        suspend fun enable() = controller.enable()

        suspend fun disable() = controller.disable()
    }

    private class FakeConsentStore(
        var state: WeatherConsentState = WeatherConsentState.DISABLED,
    ) : WeatherConsentStore {
        val writes = mutableListOf<WeatherConsentState>()
        var failNextWrite = false

        override fun read(): WeatherConsentState = state

        override fun compareAndSet(
            expectedGeneration: Long,
            next: WeatherConsentState,
        ): WeatherConsentWriteResult {
            if (failNextWrite) {
                failNextWrite = false
                return WeatherConsentWriteResult.StorageFailure
            }
            if (state.generation != expectedGeneration) {
                return WeatherConsentWriteResult.Conflict(state)
            }
            state = next
            writes += next
            return WeatherConsentWriteResult.Committed(next)
        }
    }

    private class RecordingCacheStore : ClearableWeatherCacheStore {
        val clearedKeys = mutableListOf<String>()

        override fun read(locationKey: String): WeatherCacheEntry? = null

        override fun write(entry: WeatherCacheEntry): Boolean = true

        override fun clear(locationKey: String): Boolean {
            clearedKeys += locationKey
            return true
        }
    }
}
