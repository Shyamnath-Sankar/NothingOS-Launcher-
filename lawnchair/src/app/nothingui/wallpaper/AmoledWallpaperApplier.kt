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
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.view.WindowManager
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Applies exactly one of the two bundled wallpapers to the Home target only,
 * after the caller has obtained an explicit user action. No protected
 * wallpaper image data is read; only the public ID is checked.
 */
object AmoledWallpaperApplier {

    suspend fun apply(context: Context, wallpaper: AmoledWallpaper): AmoledWallpaperApplyResult = withContext(Dispatchers.IO) {
        val manager = WallpaperManager.getInstance(context.applicationContext)
        try {
            if (!manager.isWallpaperSupported) {
                return@withContext AmoledWallpaperApplyResult.Unsupported
            }
            if (!manager.isSetWallpaperAllowed) {
                return@withContext AmoledWallpaperApplyResult.NotAllowedByPolicy
            }
            val returnedId = when (wallpaper.kind) {
                AmoledWallpaperKind.PNG -> setPng(context, manager, wallpaper)
                AmoledWallpaperKind.VECTOR -> setVector(context, manager, wallpaper)
                AmoledWallpaperKind.PROCEDURAL -> setProcedural(context, manager, wallpaper)
            }
            val currentHomeId = manager.getWallpaperId(AmoledWallpaperTarget.FLAGS)
            if (AmoledWallpaperTarget.accepted(returnedId, currentHomeId)) {
                AmoledWallpaperApplyResult.Applied(returnedId)
            } else {
                AmoledWallpaperApplyResult.Unconfirmed(returnedId, currentHomeId)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (denied: SecurityException) {
            AmoledWallpaperApplyResult.SecurityDenied
        } catch (io: IOException) {
            AmoledWallpaperApplyResult.IoFailed
        } catch (unsupported: IllegalArgumentException) {
            AmoledWallpaperApplyResult.Unsupported
        } catch (error: RuntimeException) {
            AmoledWallpaperApplyResult.Failed(error.message)
        }
    }

    private fun setPng(
        context: Context,
        manager: WallpaperManager,
        wallpaper: AmoledWallpaper,
    ): Int = context.resources.openRawResource(wallpaper.drawableRes).use { stream ->
        manager.setStream(stream, null, true, AmoledWallpaperTarget.FLAGS)
    }

    private fun setVector(
        context: Context,
        manager: WallpaperManager,
        wallpaper: AmoledWallpaper,
    ): Int {
        val drawable = context.getDrawable(wallpaper.drawableRes) ?: return 0
        val bitmap = Bitmap.createBitmap(wallpaper.widthPx, wallpaper.heightPx, Bitmap.Config.ARGB_8888)
        try {
            drawable.setBounds(0, 0, wallpaper.widthPx, wallpaper.heightPx)
            drawable.draw(Canvas(bitmap))
            return manager.setBitmap(bitmap, null, true, AmoledWallpaperTarget.FLAGS)
        } finally {
            bitmap.recycle()
        }
    }

    private fun setProcedural(
        context: Context,
        manager: WallpaperManager,
        wallpaper: AmoledWallpaper,
    ): Int {
        val spec = wallpaper.spec ?: return 0
        val (displayWidth, displayHeight) = displaySize(context)
        val size = NothingWallpaperSizes.bestFor(displayWidth, displayHeight)
        val bitmap = NothingWallpaperRenderer.render(spec, size) ?: return 0
        try {
            return manager.setBitmap(bitmap, null, true, AmoledWallpaperTarget.FLAGS)
        } finally {
            bitmap.recycle()
        }
    }

    private fun displaySize(context: Context): Pair<Int, Int> {
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        if (windowManager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            if (bounds.width() > 0 && bounds.height() > 0) {
                return bounds.width() to bounds.height()
            }
        }
        @Suppress("DEPRECATION")
        val metrics = context.resources.displayMetrics
        return metrics.widthPixels to metrics.heightPixels
    }
}
