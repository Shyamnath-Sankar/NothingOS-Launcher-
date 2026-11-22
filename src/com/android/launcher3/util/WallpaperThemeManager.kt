/*
 * Copyright (C) 2025 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.android.launcher3.util

import android.app.Activity
import android.content.ComponentCallbacks
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import app.lawnchair.theme.ThemeProvider
import app.lawnchair.theme.UiColorMode
import app.lawnchair.wallpaper.WallpaperManagerCompat
import com.android.launcher3.BuildConfig
import com.android.launcher3.LauncherConstants.SavedInstanceKeys.RUNTIME_STATE_RECREATE_TO_UPDATE_THEME
import com.android.launcher3.R
import com.android.launcher3.Utilities

/** Utility class to manage activity's theme in case it is wallpaper dependent */
class WallpaperThemeManager(private val activity: Activity) :
    OnColorHintListener, ActivityLifecycleCallbacksAdapter, ComponentCallbacks,
    WallpaperManagerCompat.OnColorsChangedListener {

    private var themeRes: Int = R.style.AppTheme

    private var recreateToUpdateTheme = false

    init {
        // Update theme
        WallpaperManagerCompat.INSTANCE.get(activity).addOnChangeListener(this);
        WallpaperColorHints.get(activity).registerOnColorHintsChangedListener(this)
        val expectedTheme = Themes.getActivityThemeRes(activity)
        if (expectedTheme != themeRes) {
            themeRes = expectedTheme
            activity.setTheme(expectedTheme)
        }
        logThemeState(expectedTheme)

        if (Utilities.ATLEAST_Q) {
            activity.registerActivityLifecycleCallbacks(this)
        } else {
            activity.application.registerActivityLifecycleCallbacks(this)
        }
        activity.registerComponentCallbacks(this)
    }

    override fun onActivitySaveInstanceState(activity: Activity, bundle: Bundle) =
        bundle.putBoolean(RUNTIME_STATE_RECREATE_TO_UPDATE_THEME, recreateToUpdateTheme)

    /**
     * A stopped activity can receive the configuration change before it is resumed, or can be
     * resumed with resources that were updated while it was not visible. Re-check the resolved
     * activity theme here so returning from Settings after a night-mode change cannot keep the
     * previous native popup/drawer theme.
     */
    override fun onActivityResumed(resumedActivity: Activity) {
        if (resumedActivity === activity) {
            updateTheme()
        }
    }

    override fun onActivityDestroyed(destroyedActivity: Activity) {
        if (destroyedActivity !== activity) return
        WallpaperManagerCompat.INSTANCE.get(activity).removeOnChangeListener(this);
        WallpaperColorHints.get(activity).unregisterOnColorsChangedListener(this)
        activity.unregisterComponentCallbacks(this)
        if (Utilities.ATLEAST_Q) {
            activity.unregisterActivityLifecycleCallbacks(this)
        } else {
            activity.application.unregisterActivityLifecycleCallbacks(this)
        }
    }

    override fun onConfigurationChanged(config: Configuration) = updateTheme()

    override fun onLowMemory() {}

    override fun onColorHintsChanged(colorHints: Int) = updateTheme()

    fun updateTheme() {
        val expectedTheme = Themes.getActivityThemeRes(activity)
        logThemeState(expectedTheme)
        if (themeRes == expectedTheme) return

        // Remember the theme before requesting recreation. The next instance applies it in init,
        // and a resume that cannot recreate immediately must not request the same recreation
        // again forever.
        themeRes = expectedTheme
        activity.setTheme(expectedTheme)
        recreateToUpdateTheme()
    }

    fun recreateToUpdateTheme() {
        recreateToUpdateTheme = true
        activity.recreate()
    }

    private fun logThemeState(expectedTheme: Int) {
        if (!BuildConfig.DEBUG) return
        val configuration = activity.resources.configuration
        val night = configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        val resolvedDark = UiColorMode(
            Themes.getAttrInteger(activity, R.attr.uiColorMode),
        ).isDarkTheme
        val expectedName = runCatching {
            activity.resources.getResourceEntryName(expectedTheme)
        }.getOrDefault("unknown")
        Log.d(TAG, "theme-refresh night=$night resolvedDark=$resolvedDark expected=$expectedName")
    }

    override fun onColorsChanged() {
        updateTheme()
    }

    companion object {
        private const val TAG = "DotWelTheme"

        /**
         * Sets a wallpaper dependent theme on this activity. The activity is automatically
         * recreated when a wallpaper change can potentially change the theme.
         */
        @JvmStatic
        fun Activity.setWallpaperDependentTheme() {
            if (!isDestroyed) {
                WallpaperThemeManager(this)
            }
        }
    }
}
