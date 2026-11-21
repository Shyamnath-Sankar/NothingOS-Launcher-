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

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LockedProfilePredicateTest {

    @Test
    fun `quiet-user flag is a locked profile`() {
        assertTrue(isLockedProfile(QUIET_USER_FLAG))
    }

    @Test
    fun `no status flags is not a locked profile`() {
        assertFalse(isLockedProfile(0))
    }

    @Test
    fun `other disabled flags are not locked profiles`() {
        assertFalse(isLockedProfile(SUSPENDED_FLAG))
        assertFalse(isLockedProfile(SAFEMODE_FLAG))
    }

    @Test
    fun `quiet-user flag combined with other flags is still locked`() {
        assertTrue(isLockedProfile(QUIET_USER_FLAG or SUSPENDED_FLAG))
    }

    private companion object {
        const val QUIET_USER_FLAG = 1 shl 3
        const val SUSPENDED_FLAG = 1 shl 2
        const val SAFEMODE_FLAG = 1 shl 0
    }
}
