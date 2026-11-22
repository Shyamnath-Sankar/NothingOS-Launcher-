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
 * Default opacity for the inherited `pref_drawerOpacity` preference.
 *
 * The key and every explicitly saved value are unchanged. Only the value used
 * when the preference has never been written differs: Play starts fully opaque,
 * while github/nightly keep the inherited half-opaque default.
 */
object DrawerOpacityDefaults {
    const val INHERITED_DEFAULT = 0.5f
    const val PLAY_DEFAULT = 1.0f

    fun forPlayFlavor(playStoreFlavor: Boolean): Float {
        return if (playStoreFlavor) PLAY_DEFAULT else INHERITED_DEFAULT
    }
}
