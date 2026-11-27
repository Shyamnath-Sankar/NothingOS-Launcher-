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

package app.nothingui.widgets

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Locks the v1.2.1 Dotwel source delta
 * (`b0330f873c8f97682ddf6b735e6210a14b14fc8a`): the headphone halo and
 * enlarged earbuds, the universal media art box and the soft battery track.
 * Text-level only, so it needs no Android runtime.
 */
class DotwelWidgetV121DeltaTest {

    private val root = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
        .first { File(it, "settings.gradle").exists() }

    private fun source(relative: String): String =
        File(root, "lawnchair/src/app/nothingui/widgets/dotwel/$relative").readText()

    @Test
    fun headphonesGrowOverALightGrayHalo() {
        val source = source("BluetoothHeadphonesWidgets.kt")
        assertTrue("missing HALO colour", source.contains("val HALO = 0xFFE9E7EC.toInt()"))
        assertTrue("square earbuds are not enlarged", source.contains("val iconSize = side * 0.36f"))
        assertTrue(
            "square earbuds are not lifted",
            source.contains("icon = box(width / 2f, height * 0.25f, iconSize, iconSize)"),
        )
        assertTrue(
            "wide earbuds are not enlarged",
            source.contains("val iconSize = min(height * 0.78f, width * 0.24f)"),
        )
        assertTrue("missing halo fill", source.contains("canvas.drawCircle(cx, haloCenterY, haloRadius, haloPaint)"))
        assertTrue(
            "missing halo edge",
            source.contains("canvas.drawCircle(cx, haloCenterY, haloRadius * 1.18f, haloEdge)"),
        )
    }

    @Test
    fun batteryMiniTrackUsesTheSoftTrack() {
        val source = source("ReferenceBatterySurface.kt")
        assertTrue(
            "mini battery track is not TRACK_SOFT",
            source.contains("canvas.drawRoundRect(rect, radius, radius, fill(TRACK_SOFT))"),
        )
        assertFalse(
            "mini battery track still uses GRAY",
            source.contains("canvas.drawRoundRect(rect, radius, radius, fill(GRAY))"),
        )
    }

    @Test
    fun mediaUniversalArtBoxIsAboutFortyPercentWide() {
        val source = source("media/ReferenceMediaCard.kt")
        assertTrue("media padding is not tightened", source.contains("val pad = side * 0.03f"))
        assertTrue(
            "media art box is not the v1.2.1 size",
            source.contains("val artSize = min(width * 0.40f, height * 0.72f)"),
        )
        assertTrue("artist height is not layout-derived", source.contains("val artistHeight: Float"))
        assertTrue("title height is not layout-derived", source.contains("val titleHeight: Float"))
        assertTrue("artist height is not used", source.contains("layout.artistHeight"))
        assertTrue("title height is not used", source.contains("layout.titleHeight"))
    }
}
