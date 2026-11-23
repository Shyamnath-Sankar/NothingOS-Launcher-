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

import android.graphics.Canvas
import android.graphics.Paint
import android.os.Handler
import android.os.HandlerThread
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.SurfaceHolder
import app.lawnchair.BuildConfig

/**
 * Original monochrome dot-field live wallpaper.
 *
 * The service owns one drawing thread per [Engine]. Frames are posted only
 * while the wallpaper is visible and its surface is valid, and every queued
 * callback is removed as soon as the wallpaper is hidden, the surface is
 * destroyed or the engine is destroyed. Nothing is downloaded, nothing is
 * persisted and no sensor, alarm, wake lock or foreground service is used.
 */
class DotFieldWallpaperService : WallpaperService() {

    override fun onCreateEngine(): Engine = DotFieldEngine()

    private inner class DotFieldEngine : Engine() {

        private val policy = DotFieldFramePolicy()
        private val policyLock = Any()
        private val renderer = DotFieldRenderer()
        private val startNanos = System.nanoTime()

        private var workerThread: HandlerThread? = null

        @Volatile
        private var worker: Handler? = null

        @Volatile
        private var surfaceHolder: SurfaceHolder? = null

        @Volatile
        private var destroyed = false

        private val frameRunnable = object : Runnable {
            override fun run() {
                drawFrame()
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            val thread = HandlerThread("dot-field-wallpaper")
            thread.start()
            workerThread = thread
            worker = Handler(thread.looper)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            synchronized(policyLock) { policy.onVisibilityChanged(visible) }
            logTransition(if (visible) "visibility=true" else "visibility=false")
            if (visible) {
                requestFrame(immediate = true)
            } else {
                stopFrames()
            }
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            surfaceHolder = holder
            val frame = holder.surfaceFrame
            synchronized(policyLock) { policy.onSurfaceCreated(frame.width(), frame.height()) }
            logTransition("surface=created ${frame.width()}x${frame.height()}")
            requestFrame(immediate = true)
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            surfaceHolder = holder
            synchronized(policyLock) { policy.onSurfaceChanged(width, height) }
            logTransition("surface=changed ${width}x$height")
            requestFrame(immediate = true)
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            synchronized(policyLock) { policy.onSurfaceDestroyed() }
            surfaceHolder = null
            stopFrames()
            logTransition("surface=destroyed")
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            destroyed = true
            synchronized(policyLock) { policy.onEngineDestroyed() }
            surfaceHolder = null
            stopFrames()
            val thread = workerThread
            workerThread = null
            worker = null
            thread?.quitSafely()
            logTransition("engine=destroyed")
            super.onDestroy()
        }

        private fun requestFrame(immediate: Boolean) {
            if (destroyed) return
            val handler = worker ?: return
            val canDraw = synchronized(policyLock) { policy.canDraw() }
            val delay = synchronized(policyLock) { policy.frameDelayMs() }
            if (!canDraw) return
            handler.removeCallbacks(frameRunnable)
            if (immediate) {
                handler.post(frameRunnable)
            } else {
                handler.postDelayed(frameRunnable, delay)
            }
        }

        private fun stopFrames() {
            worker?.removeCallbacksAndMessages(null)
        }

        private fun drawFrame() {
            if (destroyed) return
            val holder = surfaceHolder ?: return
            val geometry = synchronized(policyLock) {
                if (!policy.canDraw()) return
                policy.geometry
            } ?: return
            if (!holder.surface.isValid) {
                requestFrame(immediate = false)
                return
            }
            val elapsedMs = (System.nanoTime() - startNanos) / 1_000_000L
            val canvas = try {
                holder.lockCanvas()
            } catch (error: RuntimeException) {
                Log.w(TAG, "could not lock the wallpaper surface", error)
                null
            }
            if (canvas != null) {
                try {
                    renderer.draw(canvas, elapsedMs, geometry)
                } finally {
                    try {
                        holder.unlockCanvasAndPost(canvas)
                    } catch (error: RuntimeException) {
                        Log.w(TAG, "could not post the wallpaper frame", error)
                    }
                }
            }
            if (!destroyed) requestFrame(immediate = false)
        }

        private fun logTransition(transition: String) {
            if (BuildConfig.DEBUG) {
                Log.d(TAG, transition)
            }
        }

        override fun onSurfaceRedrawNeeded(holder: SurfaceHolder) {
            super.onSurfaceRedrawNeeded(holder)
            requestFrame(immediate = true)
        }
    }

    private class DotFieldRenderer {
        private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = DOT_COLOR
            style = Paint.Style.FILL
        }
        private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ACCENT_COLOR
            style = Paint.Style.FILL
        }

        fun draw(canvas: Canvas, elapsedMs: Long, geometry: DotFieldGeometry) {
            canvas.drawColor(BACKGROUND_COLOR)
            val phase = DotFieldMotion.phaseAt(elapsedMs)
            val offsetY = DotFieldMotion.verticalOffset(phase, geometry.spacingPx)
            var row = 0
            while (row < geometry.rows) {
                val y = row * geometry.spacingPx + offsetY
                var column = 0
                while (column < geometry.columns) {
                    val x = column * geometry.spacingPx
                    val radius = geometry.dotRadiusPx *
                        DotFieldMotion.radiusScale(row, column, phase)
                    val accent = (row * ACCENT_ROW_STRIDE + column * ACCENT_COLUMN_STRIDE) %
                        ACCENT_PERIOD == 0
                    canvas.drawCircle(x, y, radius, if (accent) accentPaint else dotPaint)
                    column++
                }
                row++
            }
        }

        companion object {
            const val BACKGROUND_COLOR: Int = 0xFF000000.toInt()
            const val DOT_COLOR: Int = 0xFF2B2B2B.toInt()
            const val ACCENT_COLOR: Int = 0xFFD7261E.toInt()
            const val ACCENT_ROW_STRIDE: Int = 7
            const val ACCENT_COLUMN_STRIDE: Int = 13
            const val ACCENT_PERIOD: Int = 211
        }
    }

    companion object {
        const val TAG: String = "DotFieldWallpaper"
    }
}
