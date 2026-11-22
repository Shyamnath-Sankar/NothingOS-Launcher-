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

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import com.android.launcher3.R

enum class AmoledWallpaperKind {
    PNG,
    VECTOR,
}

/**
 * One offline AMOLED wallpaper offered by the Play gallery. Both files are
 * compiled into the APK; nothing is downloaded at runtime.
 */
data class AmoledWallpaper(
    val id: String,
    @StringRes val titleRes: Int,
    @StringRes val creditRes: Int,
    @StringRes val changeNoticeRes: Int?,
    val sourceUrl: String,
    @DrawableRes val drawableRes: Int,
    val kind: AmoledWallpaperKind,
    val widthPx: Int,
    val heightPx: Int,
)

object AmoledWallpaperCatalog {
    const val PITCH_BLACK_ID = "pitch_black"
    const val WIREFRAME_TORUS_ID = "wireframe_torus"

    const val PITCH_BLACK_SOURCE = "https://github.com/tecdrop/pitch-black-wallpaper-images"
    const val WIREFRAME_TORUS_SOURCE = "https://walldye.com/torus-wireframe"

    val pitchBlack = AmoledWallpaper(
        id = PITCH_BLACK_ID,
        titleRes = R.string.dotwel_wallpaper_pitch_black,
        creditRes = R.string.dotwel_wallpaper_pitch_black_credit,
        changeNoticeRes = R.string.dotwel_wallpaper_pitch_black_change,
        sourceUrl = PITCH_BLACK_SOURCE,
        drawableRes = R.drawable.dotwel_wallpaper_pitch_black,
        kind = AmoledWallpaperKind.PNG,
        widthPx = 1080,
        heightPx = 1920,
    )

    val wireframeTorus = AmoledWallpaper(
        id = WIREFRAME_TORUS_ID,
        titleRes = R.string.dotwel_wallpaper_wireframe_torus,
        creditRes = R.string.dotwel_wallpaper_wireframe_torus_credit,
        changeNoticeRes = null,
        sourceUrl = WIREFRAME_TORUS_SOURCE,
        drawableRes = R.drawable.dotwel_wallpaper_wireframe_torus,
        kind = AmoledWallpaperKind.VECTOR,
        widthPx = 1080,
        heightPx = 2340,
    )

    val entries: List<AmoledWallpaper> = listOf(pitchBlack, wireframeTorus)

    fun byId(id: String): AmoledWallpaper? = entries.firstOrNull { it.id == id }
}
