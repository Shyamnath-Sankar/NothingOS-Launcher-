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

package app.nothingui.wallpaper

import android.app.WallpaperManager

/**
 * The gallery only ever changes the Home target. There is deliberately no
 * lock-screen variant and no "both" overload.
 */
object AmoledWallpaperTarget {
    const val FLAGS: Int = WallpaperManager.FLAG_SYSTEM

    fun accepted(returnedId: Int, currentHomeId: Int): Boolean = returnedId > 0 && returnedId == currentHomeId
}

sealed interface AmoledWallpaperApplyResult {
    data class Applied(val homeWallpaperId: Int) : AmoledWallpaperApplyResult

    data object Unsupported : AmoledWallpaperApplyResult

    data object NotAllowedByPolicy : AmoledWallpaperApplyResult

    data object SecurityDenied : AmoledWallpaperApplyResult

    data object IoFailed : AmoledWallpaperApplyResult

    data object Cancelled : AmoledWallpaperApplyResult

    data class Unconfirmed(val returnedId: Int, val currentHomeId: Int) : AmoledWallpaperApplyResult

    data class Failed(val message: String?) : AmoledWallpaperApplyResult
}
