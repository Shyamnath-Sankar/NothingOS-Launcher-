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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AmoledWallpaperCatalogTest {

    @Test
    fun offersTheCuratedOfflineChoices() {
        assertEquals(5, AmoledWallpaperCatalog.entries.size)
        assertEquals(
            listOf(
                AmoledWallpaperCatalog.PITCH_BLACK_ID,
                AmoledWallpaperCatalog.WIREFRAME_TORUS_ID,
                AmoledWallpaperCatalog.DOT_FIELD_ID,
                AmoledWallpaperCatalog.HORIZON_LINE_ID,
                AmoledWallpaperCatalog.GLYPH_RING_ID,
            ),
            AmoledWallpaperCatalog.entries.map { it.id },
        )
    }

    @Test
    fun everyChoiceHasResourcesCreditAndSource() {
        AmoledWallpaperCatalog.entries.forEach { wallpaper ->
            assertTrue(wallpaper.titleRes != 0)
            assertTrue(wallpaper.creditRes != 0)
            assertTrue(wallpaper.sourceUrl.startsWith("https://"))
            assertTrue(wallpaper.licenseUrl.startsWith("https://"))
            assertTrue(wallpaper.widthPx > 0)
            assertTrue(wallpaper.heightPx > 0)
            when (wallpaper.kind) {
                AmoledWallpaperKind.PROCEDURAL -> {
                    assertEquals(0, wallpaper.drawableRes)
                    assertNotNull("${wallpaper.id} needs a procedural spec", wallpaper.spec)
                }
                AmoledWallpaperKind.PNG, AmoledWallpaperKind.VECTOR -> {
                    assertTrue("${wallpaper.id} needs a bundled drawable", wallpaper.drawableRes != 0)
                    assertNull("${wallpaper.id} must not carry a procedural spec", wallpaper.spec)
                }
            }
        }
    }

    @Test
    fun everyChoiceLinksTheExactCreativeCommonsLicence() {
        assertEquals(
            "https://creativecommons.org/licenses/by/4.0/",
            AmoledWallpaperCatalog.pitchBlack.licenseUrl,
        )
        assertEquals(
            "https://creativecommons.org/publicdomain/zero/1.0/",
            AmoledWallpaperCatalog.wireframeTorus.licenseUrl,
        )
        assertEquals(
            AmoledWallpaperCatalog.CC_BY_4_0_LICENSE,
            AmoledWallpaperCatalog.pitchBlack.licenseUrl,
        )
        assertEquals(
            AmoledWallpaperCatalog.CC0_1_0_LICENSE,
            AmoledWallpaperCatalog.wireframeTorus.licenseUrl,
        )
    }

    @Test
    fun proceduralChoicesAreOriginalAndShareTheApacheLicence() {
        listOf(
            AmoledWallpaperCatalog.dotField,
            AmoledWallpaperCatalog.horizonLine,
            AmoledWallpaperCatalog.glyphRing,
        ).forEach { wallpaper ->
            assertEquals(AmoledWallpaperKind.PROCEDURAL, wallpaper.kind)
            assertEquals(AmoledWallpaperCatalog.PROJECT_SOURCE, wallpaper.sourceUrl)
            assertEquals(AmoledWallpaperCatalog.APACHE_2_0_LICENSE, wallpaper.licenseUrl)
            assertEquals(
                com.android.launcher3.R.string.dotwel_wallpaper_procedural_credit,
                wallpaper.creditRes,
            )
            assertNull(wallpaper.changeNoticeRes)
        }
    }

    @Test
    fun choicesUseDistinctBundledDrawablesAndDistinctProceduralMotifs() {
        val entries = AmoledWallpaperCatalog.entries
        assertEquals(entries.size, entries.map { it.id }.distinct().size)
        val bundled = entries.filter { it.kind != AmoledWallpaperKind.PROCEDURAL }
        assertEquals(bundled.size, bundled.map { it.drawableRes }.distinct().size)
        val procedural = entries.filter { it.kind == AmoledWallpaperKind.PROCEDURAL }
        assertEquals(procedural.size, procedural.mapNotNull { it.spec?.pattern }.distinct().size)
        assertEquals(AmoledWallpaperKind.PNG, AmoledWallpaperCatalog.pitchBlack.kind)
        assertEquals(AmoledWallpaperKind.VECTOR, AmoledWallpaperCatalog.wireframeTorus.kind)
        assertEquals(1080, AmoledWallpaperCatalog.pitchBlack.widthPx)
        assertEquals(1920, AmoledWallpaperCatalog.pitchBlack.heightPx)
        assertEquals(1080, AmoledWallpaperCatalog.wireframeTorus.widthPx)
        assertEquals(2340, AmoledWallpaperCatalog.wireframeTorus.heightPx)
    }

    @Test
    fun lookupIsExactAndTheTecdropRenameNoticeStaysVisible() {
        assertNotNull(AmoledWallpaperCatalog.byId(AmoledWallpaperCatalog.PITCH_BLACK_ID))
        assertNotNull(AmoledWallpaperCatalog.byId(AmoledWallpaperCatalog.DOT_FIELD_ID))
        assertNull(AmoledWallpaperCatalog.byId("pitch-black"))
        assertNull(AmoledWallpaperCatalog.byId(""))
        assertTrue(AmoledWallpaperCatalog.pitchBlack.changeNoticeRes != 0)
        assertNull(AmoledWallpaperCatalog.wireframeTorus.changeNoticeRes)
    }
}
