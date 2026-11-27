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

package app.nothingui.weather

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RetryAfterParserTest {

    private val now = Instant.parse("2026-11-23T12:00:00Z")

    @Test
    fun missingOrBlankValuesHaveNoBoundary() {
        assertNull(RetryAfterParser.parse(null, now))
        assertNull(RetryAfterParser.parse("", now))
        assertNull(RetryAfterParser.parse("   ", now))
    }

    @Test
    fun positiveSecondsAreRelativeToTheInjectedClock() {
        assertEquals(now.plusSeconds(120), RetryAfterParser.parse("120", now))
        assertEquals(now.plusSeconds(1), RetryAfterParser.parse(" 1 ", now))
    }

    @Test
    fun zeroOrNegativeSecondsAreRejected() {
        assertNull(RetryAfterParser.parse("0", now))
        assertNull(RetryAfterParser.parse("-30", now))
    }

    @Test
    fun anRfc1123HttpDateIsAbsolute() {
        assertEquals(
            Instant.parse("2026-11-24T22:00:00Z"),
            RetryAfterParser.parse("Tue, 24 Nov 2026 22:00:00 GMT", now),
        )
    }

    @Test
    fun malformedAndOverflowingValuesAreRejected() {
        assertNull(RetryAfterParser.parse("not-a-delay", now))
        assertNull(RetryAfterParser.parse("9223372036854775807", now))
    }
}
