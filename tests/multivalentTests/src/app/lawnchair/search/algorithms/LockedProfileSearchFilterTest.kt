/*
 * Copyright 2026, Lawnchair
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

package app.lawnchair.search.algorithms

import android.content.ComponentName
import android.content.Intent
import android.os.UserHandle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.android.launcher3.model.data.AppInfo
import com.android.launcher3.model.data.ItemInfoWithIcon
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LockedProfileSearchFilterTest {

    @Test
    fun `unlocked profile app is kept`() {
        val app = appInfo()

        assertThat(sequenceOf(app).filterLockedProfiles().toList()).containsExactly(app)
    }

    @Test
    fun `locked profile app is dropped`() {
        val app = appInfo().apply {
            runtimeStatusFlags = ItemInfoWithIcon.FLAG_DISABLED_QUIET_USER
        }

        assertThat(sequenceOf(app).filterLockedProfiles().toList()).isEmpty()
    }

    @Test
    fun `app disabled for another reason is kept`() {
        val app = appInfo().apply {
            runtimeStatusFlags = ItemInfoWithIcon.FLAG_DISABLED_SUSPENDED
        }

        assertThat(sequenceOf(app).filterLockedProfiles().toList()).containsExactly(app)
    }

    private fun appInfo() = AppInfo(
        ComponentName(PACKAGE_NAME, "$PACKAGE_NAME.MainActivity"),
        "App",
        UserHandle.of(10),
        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
    )

    private companion object {
        const val PACKAGE_NAME = "com.example.lockedprofile"
    }
}
