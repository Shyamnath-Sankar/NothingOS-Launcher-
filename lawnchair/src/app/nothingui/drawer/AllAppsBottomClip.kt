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

package app.nothingui.drawer

/**
 * Bottom drawing boundary for the all-apps list.
 *
 * The recycler already reserves the navigation bar and any floating bottom
 * search bar through its bottom padding, but `all_apps_rv_layout.xml` keeps
 * `clipToPadding="false"` so scrolled children can paint into that reserved
 * area. This helper returns the bottom edge the Play drawer clips its children
 * to, leaving the top padding overflow untouched for floating headers.
 *
 * Returns [NO_CLIP] when the Play gate is off or there is no bottom padding, so
 * non-Play and unpadded layouts keep the inherited drawing behavior.
 */
object AllAppsBottomClip {
    const val NO_CLIP = -1

    fun clipBottom(enabled: Boolean, height: Int, paddingBottom: Int): Int {
        if (!enabled || paddingBottom <= 0) return NO_CLIP
        return (height - paddingBottom).coerceAtLeast(0)
    }
}
