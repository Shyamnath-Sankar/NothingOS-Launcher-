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

/**
 * Pure one-shot bookkeeping for [WidgetPickerRequest]. Only the latest request can be pending,
 * completing a superseded request is refused, and a handled id is never accepted twice.
 */
class WidgetPickerRequestState {
    var handledId: String? = null
        private set
    var pendingId: String? = null
        private set

    fun offer(id: String?): Boolean {
        if (id.isNullOrEmpty() || id == handledId) {
            return false
        }
        handledId = id
        pendingId = id
        return true
    }

    fun isPending(): Boolean = pendingId != null

    fun matches(id: String?): Boolean = id != null && id == pendingId

    fun complete(id: String?): Boolean {
        if (!matches(id)) {
            return false
        }
        pendingId = null
        return true
    }

    fun cancel() {
        pendingId = null
    }

    fun restoreHandled(id: String?) {
        handledId = id
    }
}
