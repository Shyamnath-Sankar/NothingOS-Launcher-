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

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class WeatherSettingsDraft(
    val label: String = "",
    val latitudeText: String = "",
    val longitudeText: String = "",
    val consentChecked: Boolean = false,
)

enum class WeatherSettingsMessage {
    ENABLED,
    DISABLED,
    REVOKED_BY_EDIT,
    INVALID_LOCATION,
    CONSENT_REQUIRED,
    STORAGE_FAILURE,
    REVOKE_UNCONFIRMED,
    CONFLICT,
}

data class WeatherSettingsUiState(
    val saved: WeatherConsentState = WeatherConsentState.DISABLED,
    val draft: WeatherSettingsDraft = WeatherSettingsDraft(),
    val validation: WeatherLocationInput = WeatherConsentPolicy.parseLocation("", "", ""),
    val message: WeatherSettingsMessage? = null,
    val busy: Boolean = false,
    val loading: Boolean = false,
    val showValidationErrors: Boolean = false,
    /**
     * True while the in-process session is already off but the stored opt-in
     * has not been confirmed disabled. The UI must keep the retry action
     * available instead of claiming a durable disable.
     */
    val revocationPending: Boolean = false,
) {
    val isEnabled: Boolean
        get() = saved.enabled

    val canEnable: Boolean
        get() = !loading && !saved.enabled && !busy && !revocationPending &&
            draft.consentChecked && validation is WeatherLocationInput.Valid

    val canDisable: Boolean
        get() = !loading && !busy && (saved.enabled || revocationPending)
}

/**
 * State holder for the real Weather settings screen. All persisted changes go
 * through [WeatherConsentStore]; typing alone never enables, and editing an
 * enabled location first tells [consentObserver] to stop the visible session
 * and then revokes the durable opt-in before the old cache is removed.
 *
 * The observer is the single boundary next phase will connect to
 * [WeatherSessionController]. No network, worker, alarm or timer is constructed
 * here.
 */
class WeatherSettingsController(
    private val store: WeatherConsentStore,
    private val cacheStore: ClearableWeatherCacheStore? = null,
    private val consentObserver: (WeatherConsentState) -> Unit = {},
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(WeatherSettingsUiState(loading = true))
    private var loaded = false

    val state: StateFlow<WeatherSettingsUiState> = _state.asStateFlow()

    /** Reads the persisted consent off the main thread before the screen is editable. */
    suspend fun load() {
        mutex.withLock {
            if (loaded) return@withLock
            val saved = withContext(ioDispatcher) { store.read() }
            _state.value = initialState(saved)
            loaded = true
            consentObserver(saved)
        }
    }

    suspend fun onDraftChanged(draft: WeatherSettingsDraft) {
        if (_state.value.loading || _state.value.busy) return
        _state.update {
            it.copy(
                draft = draft,
                validation = validate(draft),
                message = null,
                showValidationErrors = true,
            )
        }
        revokeIfEnabledLocationChanged()
    }

    suspend fun enable() {
        mutex.withLock {
            val snapshot = _state.value
            if (snapshot.loading || snapshot.saved.enabled || snapshot.revocationPending) {
                return@withLock
            }
            when (val validation = snapshot.validation) {
                is WeatherLocationInput.Invalid -> {
                    _state.update {
                        it.copy(
                            message = WeatherSettingsMessage.INVALID_LOCATION,
                            showValidationErrors = true,
                        )
                    }
                    return@withLock
                }

                is WeatherLocationInput.Valid -> {
                    if (!snapshot.draft.consentChecked) {
                        _state.update { it.copy(message = WeatherSettingsMessage.CONSENT_REQUIRED) }
                        return@withLock
                    }
                    val next = WeatherConsentPolicy.enable(snapshot.saved, validation.location)
                    _state.update { it.copy(busy = true, message = null) }
                    val outcome = withContext(ioDispatcher) {
                        store.compareAndSet(snapshot.saved.generation, next)
                    }
                    when (outcome) {
                        is WeatherConsentWriteResult.Committed -> {
                            _state.update {
                                it.copy(
                                    saved = outcome.state,
                                    draft = it.draft.copy(consentChecked = false),
                                    busy = false,
                                    message = WeatherSettingsMessage.ENABLED,
                                    showValidationErrors = false,
                                )
                            }
                            consentObserver(outcome.state)
                        }

                        is WeatherConsentWriteResult.Conflict -> {
                            _state.update {
                                it.copy(
                                    saved = outcome.current,
                                    busy = false,
                                    message = WeatherSettingsMessage.CONFLICT,
                                )
                            }
                        }

                        WeatherConsentWriteResult.StorageFailure -> {
                            _state.update {
                                it.copy(
                                    busy = false,
                                    message = WeatherSettingsMessage.STORAGE_FAILURE,
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * Stops the in-process session immediately and then asks the store to
     * revoke the durable opt-in. A failed write is not reported as a completed
     * disable: the screen stays off, [WeatherSettingsUiState.revocationPending]
     * stays true and this method remains callable for an explicit retry.
     */
    suspend fun disable() {
        mutex.withLock {
            val snapshot = _state.value
            if (snapshot.loading || snapshot.busy) return@withLock
            val local = snapshot.saved
            if (!local.enabled && !snapshot.revocationPending) return@withLock
            val stopped = if (local.enabled) WeatherConsentPolicy.disable(local) else local
            consentObserver(stopped)
            _state.update {
                it.copy(
                    saved = stopped,
                    busy = true,
                    message = null,
                    showValidationErrors = false,
                    revocationPending = true,
                )
            }
            val persisted = withContext(ioDispatcher) { store.read() }
            val outcome = withContext(ioDispatcher) { persistRevoked(persisted) }
            finishRevoke(
                outcome = outcome,
                cacheKeys = cacheKeysOf(local, persisted),
                successMessage = WeatherSettingsMessage.DISABLED,
                clearDraftOnCommit = true,
            )
        }
    }

    private suspend fun revokeIfEnabledLocationChanged() {
        mutex.withLock {
            val snapshot = _state.value
            val saved = snapshot.saved
            if (!saved.enabled || !locationChanged(saved, snapshot.draft)) return@withLock
            val revoked = WeatherConsentPolicy.revokeForEdit(saved)
            consentObserver(revoked)
            _state.update {
                it.copy(
                    saved = revoked,
                    draft = it.draft.copy(consentChecked = false),
                    busy = true,
                    message = null,
                    showValidationErrors = true,
                    revocationPending = true,
                )
            }
            val persisted = withContext(ioDispatcher) { store.read() }
            val outcome = withContext(ioDispatcher) { persistRevoked(persisted) }
            finishRevoke(
                outcome = outcome,
                cacheKeys = cacheKeysOf(saved, persisted),
                successMessage = WeatherSettingsMessage.REVOKED_BY_EDIT,
                clearDraftOnCommit = false,
            )
        }
    }

    private suspend fun finishRevoke(
        outcome: WeatherConsentWriteResult,
        cacheKeys: Set<String>,
        successMessage: WeatherSettingsMessage,
        clearDraftOnCommit: Boolean,
    ) {
        when (outcome) {
            is WeatherConsentWriteResult.Committed -> {
                clearCaches(cacheKeys)
                _state.update {
                    it.copy(
                        saved = outcome.state,
                        draft = if (clearDraftOnCommit) WeatherSettingsDraft() else it.draft,
                        validation = if (clearDraftOnCommit) validate(WeatherSettingsDraft()) else it.validation,
                        busy = false,
                        message = successMessage,
                        showValidationErrors = if (clearDraftOnCommit) false else it.showValidationErrors,
                        revocationPending = false,
                    )
                }
            }

            is WeatherConsentWriteResult.Conflict -> {
                if (!outcome.current.enabled) {
                    clearCaches(cacheKeys)
                    _state.update {
                        it.copy(
                            saved = outcome.current,
                            draft = if (clearDraftOnCommit) WeatherSettingsDraft() else it.draft,
                            validation = if (clearDraftOnCommit) validate(WeatherSettingsDraft()) else it.validation,
                            busy = false,
                            message = successMessage,
                            showValidationErrors = if (clearDraftOnCommit) false else it.showValidationErrors,
                            revocationPending = false,
                        )
                    }
                } else {
                    _state.update {
                        it.copy(
                            busy = false,
                            message = WeatherSettingsMessage.CONFLICT,
                            revocationPending = true,
                        )
                    }
                }
            }

            WeatherConsentWriteResult.StorageFailure -> {
                _state.update {
                    it.copy(
                        busy = false,
                        message = WeatherSettingsMessage.REVOKE_UNCONFIRMED,
                        revocationPending = true,
                    )
                }
            }
        }
    }

    private suspend fun clearCaches(cacheKeys: Set<String>) {
        for (key in cacheKeys) {
            withContext(ioDispatcher) { cacheStore?.clear(key) }
        }
    }

    private fun cacheKeysOf(
        vararg states: WeatherConsentState,
    ): Set<String> = states.mapNotNull { it.location?.cacheKey }.toSet()

    /**
     * A revoke is retried against the newest stored generation, so a disable or
     * edit cannot lose to a stale enable written concurrently. Enable is not
     * retried: a stale draft must be shown as a conflict instead of enabling a
     * location the user did not just confirm.
     */
    private fun persistRevoked(initial: WeatherConsentState): WeatherConsentWriteResult {
        var current = initial
        repeat(MAX_REVOKE_ATTEMPTS) {
            val next = WeatherConsentPolicy.disable(current)
            when (val result = store.compareAndSet(current.generation, next)) {
                is WeatherConsentWriteResult.Committed -> return result
                is WeatherConsentWriteResult.Conflict -> current = result.current
                WeatherConsentWriteResult.StorageFailure -> return result
            }
        }
        return WeatherConsentWriteResult.Conflict(current)
    }

    private fun locationChanged(
        saved: WeatherConsentState,
        draft: WeatherSettingsDraft,
    ): Boolean {
        val savedLocation = saved.location ?: return false
        return when (val input = validate(draft)) {
            is WeatherLocationInput.Valid -> input.location != savedLocation
            is WeatherLocationInput.Invalid -> true
        }
    }

    private fun validate(draft: WeatherSettingsDraft): WeatherLocationInput = WeatherConsentPolicy.parseLocation(
        label = draft.label,
        latitudeText = draft.latitudeText,
        longitudeText = draft.longitudeText,
    )

    private fun initialState(saved: WeatherConsentState): WeatherSettingsUiState {
        val draft = saved.location?.let {
            WeatherSettingsDraft(
                label = it.label,
                latitudeText = it.coordinates.latitudeText,
                longitudeText = it.coordinates.longitudeText,
            )
        } ?: WeatherSettingsDraft()
        return WeatherSettingsUiState(
            saved = saved,
            draft = draft,
            validation = validate(draft),
            message = null,
            busy = false,
            loading = false,
        )
    }

    private companion object {
        const val MAX_REVOKE_ATTEMPTS = 3
    }
}
