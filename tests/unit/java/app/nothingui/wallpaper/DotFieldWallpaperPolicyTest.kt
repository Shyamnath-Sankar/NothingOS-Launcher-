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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DotFieldWallpaperPolicyTest {

    @Test
    fun aFreshEngineDrawsNothing() {
        val policy = DotFieldFramePolicy()

        assertFalse(policy.canDraw())
        assertNull(policy.geometry)
    }

    @Test
    fun drawingNeedsBothVisibilityAndAValidSurface() {
        val policy = DotFieldFramePolicy()

        policy.onSurfaceCreated(width = 1080, height = 2400)
        assertFalse(policy.canDraw())

        policy.onVisibilityChanged(visible = true)
        assertTrue(policy.canDraw())

        policy.onVisibilityChanged(visible = false)
        assertFalse(policy.canDraw())

        policy.onVisibilityChanged(visible = true)
        assertTrue(policy.canDraw())
    }

    @Test
    fun zeroOrNegativeSurfaceDimensionsStayInvalid() {
        listOf(0 to 2400, 1080 to 0, -1 to 2400, 1080 to -1, 0 to 0).forEach { (width, height) ->
            val policy = DotFieldFramePolicy()
            policy.onVisibilityChanged(visible = true)
            policy.onSurfaceCreated(width = width, height = height)

            assertFalse("${width}x$height must not draw", policy.canDraw())
            assertNull(policy.geometry)
        }
    }

    @Test
    fun resizingReplacesTheGeometryAndKeepsDrawingSafe() {
        val policy = DotFieldFramePolicy()
        policy.onVisibilityChanged(visible = true)
        policy.onSurfaceChanged(width = 1080, height = 2400)
        val portrait = policy.geometry

        assertNotNull(portrait)
        assertEquals(1080, portrait!!.widthPx)
        assertEquals(2400, portrait.heightPx)

        policy.onSurfaceChanged(width = 2400, height = 1080)
        val landscape = policy.geometry

        assertNotNull(landscape)
        assertEquals(2400, landscape!!.widthPx)
        assertEquals(1080, landscape.heightPx)
        assertTrue(policy.canDraw())
    }

    @Test
    fun surfaceDestroyOrEngineDestroyStopsEveryFutureFrame() {
        val policy = DotFieldFramePolicy()
        policy.onVisibilityChanged(visible = true)
        policy.onSurfaceChanged(width = 1080, height = 2400)
        assertTrue(policy.canDraw())

        policy.onSurfaceDestroyed()
        assertFalse(policy.canDraw())

        policy.onSurfaceChanged(width = 1080, height = 2400)
        policy.onEngineDestroyed()
        assertFalse(policy.canDraw())

        policy.onVisibilityChanged(visible = true)
        policy.onSurfaceChanged(width = 1080, height = 2400)
        assertFalse("a destroyed engine never resumes", policy.canDraw())
        assertNull(policy.geometry)
    }

    @Test
    fun theFrameCadenceIsAboutFifteenFpsAndNeverZero() {
        val policy = DotFieldFramePolicy()

        assertEquals(DotFieldFramePolicy.DEFAULT_FRAME_INTERVAL_MS, policy.frameDelayMs())
        assertTrue(policy.frameDelayMs() >= DotFieldFramePolicy.MIN_FRAME_INTERVAL_MS)
        assertTrue(DotFieldFramePolicy.DEFAULT_FRAME_INTERVAL_MS in 60L..70L)
        assertTrue(DotFieldFramePolicy(frameIntervalMs = 0L).frameDelayMs() >= 1L)
    }

    @Test
    fun geometryIsDeterministicBoundedAndFitsTheSurface() {
        val first = DotFieldGeometry.from(widthPx = 1080, heightPx = 2400)
        val second = DotFieldGeometry.from(widthPx = 1080, heightPx = 2400)

        assertEquals(first, second)
        assertNotNull(first)
        assertTrue(first!!.columns > 1)
        assertTrue(first.rows > 1)
        assertTrue(first.spacingPx >= DotFieldGeometry.MIN_SPACING_PX)
        assertTrue(first.spacingPx <= DotFieldGeometry.MAX_SPACING_PX)
        assertTrue(first.dotRadiusPx > 0f)
        assertTrue(first.dotRadiusPx < first.spacingPx)
        assertTrue(first.columns.toFloat() * first.spacingPx >= first.widthPx)
        assertTrue(first.rows.toFloat() * first.spacingPx >= first.heightPx)
    }

    @Test
    fun theSlowMotionPhaseStaysBoundedAndRepeats() {
        listOf(0L, 1L, 1234L, 14_000L, 28_000L, 999_999L).forEach { elapsed ->
            val phase = DotFieldMotion.phaseAt(elapsed)
            assertTrue(phase >= 0f)
            assertTrue(phase < (2.0 * Math.PI).toFloat())
            assertEquals(phase, DotFieldMotion.phaseAt(elapsed + (DotFieldMotion.PERIOD_MS * 2).toLong()), 0.0001f)
        }
        assertEquals(0f, DotFieldMotion.phaseAt(0L), 0f)
    }

    @Test
    fun theRadiusPulseIsRestrainedAndPositive() {
        var phase = 0f
        while (phase < (2.0 * Math.PI).toFloat()) {
            val scale = DotFieldMotion.radiusScale(row = 3, column = 7, phase = phase)
            assertTrue(scale in 0.6f..1.0f)
            phase += 0.25f
        }
    }
}
