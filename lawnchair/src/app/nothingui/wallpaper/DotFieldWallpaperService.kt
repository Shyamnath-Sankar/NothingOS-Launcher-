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
import com.android.launcher3.BuildConfig
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

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
        private val lock = ReentrantLock()
        private val idle = lock.newCondition()
        private val renderer = DotFieldRenderer()
        private val startNanos = System.nanoTime()

        private var workerThread: HandlerThread? = null
        private var worker: Handler? = null
        private var surfaceHolder: SurfaceHolder? = null
        private var destroyed = false
        private var framePending = false
        private var drawing = false
        private var postedFrames = 0L
        private var drawnFrames = 0L
        private var activeHolder: SurfaceHolder? = null
        private var activeGeometry: DotFieldGeometry? = null

        private val frameRunnable = object : Runnable {
            override fun run() {
                drawFrame()
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            val thread = HandlerThread("dot-field-wallpaper")
            thread.start()
            lock.withLock {
                workerThread = thread
                worker = Handler(thread.looper)
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            super.onVisibilityChanged(visible)
            lock.withLock { policy.onVisibilityChanged(visible) }
            if (visible) {
                requestFrame(immediate = true)
                logTransition("visibility=true")
            } else {
                cancelAndAwaitIdle()
                logTransition("visibility=false")
            }
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            val frame = holder.surfaceFrame
            lock.withLock {
                surfaceHolder = holder
                policy.onSurfaceCreated(frame.width(), frame.height())
            }
            requestFrame(immediate = true)
            logTransition("surface=created ${frame.width()}x${frame.height()}")
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            lock.withLock {
                surfaceHolder = holder
                policy.onSurfaceChanged(width, height)
            }
            requestFrame(immediate = true)
            logTransition("surface=changed ${width}x$height")
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            lock.withLock { policy.onSurfaceDestroyed() }
            cancelAndAwaitIdle()
            lock.withLock { surfaceHolder = null }
            logTransition("surface=destroyed")
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            lock.withLock {
                destroyed = true
                policy.onEngineDestroyed()
            }
            cancelAndAwaitIdle()
            val thread = lock.withLock {
                surfaceHolder = null
                val current = workerThread
                workerThread = null
                worker = null
                current
            }
            thread?.quitSafely()
            logTransition("engine=destroyed")
            super.onDestroy()
        }

        /**
         * Gate and enqueue are one atomic step under [lock]. A teardown removes
         * queued callbacks under the same lock, so a frame can never be posted
         * after hidden/destroy removed the pending callbacks.
         */
        private fun requestFrame(immediate: Boolean) {
            lock.withLock {
                if (destroyed) return
                val handler = worker ?: return
                if (!policy.canDraw()) return
                if (framePending || drawing) return
                framePending = true
                postedFrames++
                if (immediate) {
                    handler.post(frameRunnable)
                } else {
                    handler.postDelayed(frameRunnable, policy.frameDelayMs())
                }
            }
        }

        /**
         * Remove any queued frame and wait for an in-flight draw to finish
         * before returning. await() releases the lock, so the worker can
         * publish its completion; no join happens while the lock is held.
         */
        private fun cancelAndAwaitIdle() {
            lock.withLock {
                worker?.removeCallbacksAndMessages(null)
                framePending = false
                var interrupted = false
                while (drawing) {
                    try {
                        idle.await()
                    } catch (interruptedError: InterruptedException) {
                        interrupted = true
                    }
                }
                if (interrupted) Thread.currentThread().interrupt()
            }
        }

        private fun drawFrame() {
            if (!beginFrame()) return
            val holder = activeHolder
            val geometry = activeGeometry
            if (holder == null || geometry == null) {
                finishFrame(drew = false)
                return
            }
            var drew = false
            try {
                if (holder.surface.isValid) {
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
                        drew = true
                    }
                }
            } finally {
                finishFrame(drew)
            }
            requestFrame(immediate = false)
        }

        private fun beginFrame(): Boolean {
            lock.withLock {
                if (!framePending) return false
                framePending = false
                if (destroyed || !policy.canDraw()) return false
                val holder = surfaceHolder ?: return false
                val geometry = policy.geometry ?: return false
                activeHolder = holder
                activeGeometry = geometry
                drawing = true
                return true
            }
        }

        private fun finishFrame(drew: Boolean) {
            lock.withLock {
                if (drew) drawnFrames++
                activeHolder = null
                activeGeometry = null
                drawing = false
                idle.signalAll()
            }
        }

        private fun logTransition(transition: String) {
            if (!BuildConfig.DEBUG) return
            val counters = lock.withLock {
                "posted=$postedFrames drawn=$drawnFrames pending=$framePending drawing=$drawing"
            }
            Log.d(TAG, "$transition $counters")
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
