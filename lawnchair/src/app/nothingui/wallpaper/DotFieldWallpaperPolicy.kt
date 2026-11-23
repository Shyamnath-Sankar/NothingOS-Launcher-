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

import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * Pure lifecycle and scheduling policy for the dot-field live wallpaper.
 *
 * It deliberately imports no Android type so the frame gate can be unit-tested
 * on the JVM. A frame may only be posted while the engine is alive, the
 * wallpaper is visible and the surface has a usable, non-zero size.
 */
class DotFieldFramePolicy(
    private val frameIntervalMs: Long = DEFAULT_FRAME_INTERVAL_MS,
) {
    var isVisible: Boolean = false
        private set

    var isSurfaceValid: Boolean = false
        private set

    var isDestroyed: Boolean = false
        private set

    var geometry: DotFieldGeometry? = null
        private set

    fun onVisibilityChanged(visible: Boolean) {
        if (isDestroyed) return
        isVisible = visible
    }

    fun onSurfaceCreated(width: Int, height: Int) {
        if (isDestroyed) return
        onSurfaceChanged(width, height)
    }

    fun onSurfaceChanged(width: Int, height: Int) {
        if (isDestroyed) return
        val next = DotFieldGeometry.from(width, height)
        geometry = next
        isSurfaceValid = next != null
    }

    fun onSurfaceDestroyed() {
        isSurfaceValid = false
    }

    /**
     * Once destroyed the engine is terminal: a late surface or visibility
     * callback can never schedule another frame.
     */
    fun onEngineDestroyed() {
        isDestroyed = true
        isVisible = false
        isSurfaceValid = false
        geometry = null
    }

    fun canDraw(): Boolean = !isDestroyed && isVisible && isSurfaceValid && geometry != null

    fun frameDelayMs(): Long = frameIntervalMs.coerceAtLeast(MIN_FRAME_INTERVAL_MS)

    companion object {
        /** ~15 fps while the wallpaper is visible. */
        const val DEFAULT_FRAME_INTERVAL_MS: Long = 66L
        const val MIN_FRAME_INTERVAL_MS: Long = 1L
    }
}

/**
 * Deterministic, original dot-field layout derived from the real surface size.
 * The grid is coarse and the dots small so the result stays quiet on Home.
 */
data class DotFieldGeometry(
    val widthPx: Int,
    val heightPx: Int,
    val columns: Int,
    val rows: Int,
    val spacingPx: Float,
    val dotRadiusPx: Float,
) {
    companion object {
        const val TARGET_SHORT_SIDE_DOTS: Int = 26
        const val MIN_SPACING_PX: Float = 8f
        const val MAX_SPACING_PX: Float = 96f
        const val DOT_RADIUS_FRACTION: Float = 0.09f

        fun from(widthPx: Int, heightPx: Int): DotFieldGeometry? {
            if (widthPx <= 0 || heightPx <= 0) return null
            val shortSide = min(widthPx, heightPx).toFloat()
            val spacing = (shortSide / TARGET_SHORT_SIDE_DOTS)
                .coerceIn(MIN_SPACING_PX, MAX_SPACING_PX)
            val columns = (widthPx / spacing).toInt() + 2
            val rows = (heightPx / spacing).toInt() + 2
            val radius = (spacing * DOT_RADIUS_FRACTION).coerceAtLeast(0.5f)
            return DotFieldGeometry(
                widthPx = widthPx,
                heightPx = heightPx,
                columns = columns,
                rows = rows,
                spacingPx = spacing,
                dotRadiusPx = radius,
            )
        }
    }
}

/**
 * Restrained, periodic motion. The period is long on purpose; the wallpaper
 * should feel static at a glance and simply breathe over many seconds.
 */
object DotFieldMotion {
    const val PERIOD_MS: Long = 14_000L
    private const val TWO_PI = (2.0 * PI).toFloat()
    private const val BASE_RADIUS_SCALE = 0.8f
    private const val PULSE_RANGE = 0.2f
    private const val PHASE_STEP = 0.15f
    private const val DRIFT_FRACTION = 0.28f

    fun phaseAt(elapsedMs: Long): Float {
        val normalized = (elapsedMs % PERIOD_MS).toFloat() / PERIOD_MS.toFloat()
        return normalized * TWO_PI
    }

    fun radiusScale(row: Int, column: Int, phase: Float): Float {
        val wave = sin(phase + (row + column) * PHASE_STEP)
        return BASE_RADIUS_SCALE + PULSE_RANGE * ((wave + 1f) * 0.5f)
    }

    fun verticalOffset(phase: Float, spacingPx: Float): Float = sin(phase) * spacingPx * DRIFT_FRACTION
}
