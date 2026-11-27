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

package app.nothingui.widgets

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NothingUiDeviceStorageTest {

    private val gb = 1024L * 1024L * 1024L
    private val mb = 1024L * 1024L

    @Test
    fun knownReadingRequiresAPositiveTotalAndAvailableWithinIt() {
        assertTrue(NothingUiDeviceStorage.isKnown(100 * gb, 48 * gb))
        assertTrue(NothingUiDeviceStorage.isKnown(100 * gb, 0L))
        assertTrue(NothingUiDeviceStorage.isKnown(100 * gb, 100 * gb))
        assertFalse(NothingUiDeviceStorage.isKnown(0L, 0L))
        assertFalse(NothingUiDeviceStorage.isKnown(-1L, 0L))
        assertFalse(NothingUiDeviceStorage.isKnown(100 * gb, -1L))
        assertFalse(NothingUiDeviceStorage.isKnown(100 * gb, 101 * gb))
    }

    @Test
    fun formatsBytesInBinaryUnits() {
        assertEquals("0 B", NothingUiDeviceStorage.formatSize(0L, Locale.US))
        assertEquals("512 B", NothingUiDeviceStorage.formatSize(512L, Locale.US))
        assertEquals("1.0 KB", NothingUiDeviceStorage.formatSize(1024L, Locale.US))
        assertEquals("1.5 MB", NothingUiDeviceStorage.formatSize(mb + mb / 2, Locale.US))
        assertEquals("48.2 GB", NothingUiDeviceStorage.formatSize(48 * gb + gb / 5, Locale.US))
        assertEquals("1.0 TB", NothingUiDeviceStorage.formatSize(1024L * gb, Locale.US))
    }

    @Test
    fun negativeBytesRenderTheUnknownDashInsteadOfAFakeSize() {
        assertEquals("--", NothingUiDeviceStorage.formatSize(-1L, Locale.US))
    }

    @Test
    fun usedPercentIsClampedToTheBoundedProgressRange() {
        assertEquals(0, NothingUiDeviceStorage.usedPercent(100 * gb, 100 * gb))
        assertEquals(100, NothingUiDeviceStorage.usedPercent(100 * gb, 0L))
        assertEquals(52, NothingUiDeviceStorage.usedPercent(100 * gb, 48 * gb))
        assertEquals(50, NothingUiDeviceStorage.usedPercent(2L, 1L))
        assertEquals(67, NothingUiDeviceStorage.usedPercent(3L, 1L))
    }

    @Test
    fun unknownReadingsNeverProduceAGuessedPercentage() {
        assertEquals(
            NothingUiDeviceStorage.UNKNOWN_PERCENT,
            NothingUiDeviceStorage.usedPercent(0L, 0L),
        )
        assertEquals(
            NothingUiDeviceStorage.UNKNOWN_PERCENT,
            NothingUiDeviceStorage.usedPercent(100 * gb, -1L),
        )
        assertEquals(
            NothingUiDeviceStorage.UNKNOWN_PERCENT,
            NothingUiDeviceStorage.usedPercent(100 * gb, 101 * gb),
        )
        assertEquals(0, NothingUiDeviceStorage.progress(0L, 0L))
    }
}
