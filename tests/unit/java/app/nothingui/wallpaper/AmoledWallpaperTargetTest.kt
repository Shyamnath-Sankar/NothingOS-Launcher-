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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AmoledWallpaperTargetTest {

    @Test
    fun targetsTheHomeWallpaperOnly() {
        assertEquals(WallpaperManager.FLAG_SYSTEM, AmoledWallpaperTarget.FLAGS)
        assertFalse(AmoledWallpaperTarget.FLAGS and WallpaperManager.FLAG_LOCK != 0)
    }

    @Test
    fun successNeedsAPositiveReturnedIdEqualToTheCurrentHomeId() {
        assertTrue(AmoledWallpaperTarget.accepted(returnedId = 42, currentHomeId = 42))
        assertFalse(AmoledWallpaperTarget.accepted(returnedId = 0, currentHomeId = 42))
        assertFalse(AmoledWallpaperTarget.accepted(returnedId = -1, currentHomeId = 42))
        assertFalse(AmoledWallpaperTarget.accepted(returnedId = 42, currentHomeId = 43))
        assertFalse(AmoledWallpaperTarget.accepted(returnedId = 43, currentHomeId = 42))
    }
}
