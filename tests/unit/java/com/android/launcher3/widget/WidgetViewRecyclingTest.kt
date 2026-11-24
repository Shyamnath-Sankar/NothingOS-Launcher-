/*
 * Copyright (C) 2026 The Android Open Source Project
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
package com.android.launcher3.widget

import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class WidgetViewRecyclingTest {
    @Test
    fun recycledViewWithoutTag_keepsOriginalItem() {
        val item = Any()

        assertSame(item, WidgetViewRecycling.resolveItemTag(item, null))
    }

    @Test
    fun recycledViewWithTag_isNotClobbered() {
        val original = Any()
        val recycled = Any()

        assertSame(recycled, WidgetViewRecycling.resolveItemTag(original, recycled))
    }

    @Test
    fun viewsWithoutTag_stayUntagged() {
        assertNull(WidgetViewRecycling.resolveItemTag(null, null))
    }
}
