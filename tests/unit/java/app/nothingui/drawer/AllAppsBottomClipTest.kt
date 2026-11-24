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

import org.junit.Assert.assertEquals
import org.junit.Test

class AllAppsBottomClipTest {

    @Test
    fun nonPlayKeepsInheritedDrawing() {
        assertEquals(AllAppsBottomClip.NO_CLIP, AllAppsBottomClip.clipBottom(false, 1920, 144))
    }

    @Test
    fun zeroInsetKeepsInheritedDrawing() {
        assertEquals(AllAppsBottomClip.NO_CLIP, AllAppsBottomClip.clipBottom(true, 1920, 0))
    }

    @Test
    fun negativeInsetKeepsInheritedDrawing() {
        assertEquals(AllAppsBottomClip.NO_CLIP, AllAppsBottomClip.clipBottom(true, 1920, -1))
    }

    @Test
    fun playClipsAboveTheReservedBottom() {
        assertEquals(1776, AllAppsBottomClip.clipBottom(true, 1920, 144))
    }

    @Test
    fun exactFitClampsToZero() {
        assertEquals(0, AllAppsBottomClip.clipBottom(true, 144, 144))
    }

    @Test
    fun oversizedPaddingClampsToZero() {
        assertEquals(0, AllAppsBottomClip.clipBottom(true, 144, 1920))
    }

    @Test
    fun nonPositiveHeightClampsToZero() {
        assertEquals(0, AllAppsBottomClip.clipBottom(true, 0, 10))
        assertEquals(0, AllAppsBottomClip.clipBottom(true, -5, 10))
    }
}
