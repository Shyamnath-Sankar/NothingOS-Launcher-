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

package com.android.launcher3.touch;

import android.util.Log;

import com.android.launcher3.BuildConfig;

/**
 * Temporary debug-only trace for the app-drawer swipe on the Play channel.
 *
 * <p>This exists solely to collect runtime evidence from the API 37 smoke run. It is compiled
 * out of release and non-Play builds by the {@link #ENABLED} constant and must be removed once
 * the gesture routing is fixed.
 */
public final class DotwelDrawerTrace {

    public static final String TAG = "DotwelDrawerTrace";
    public static final boolean ENABLED =
            BuildConfig.DEBUG && "play".equals(BuildConfig.FLAVOR_channel);

    private DotwelDrawerTrace() {
    }

    public static void log(String message) {
        if (ENABLED) {
            Log.d(TAG, message);
        }
    }
}
