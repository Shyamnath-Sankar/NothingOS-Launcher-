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

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class WeatherCoordinatesTest {

    @Test
    fun coordinatesRoundToFourDecimalsAndShareACacheKey() {
        val first = WeatherCoordinates.from(latitude = 51.50744111, longitude = -0.12784111)
        val second = WeatherCoordinates.from(latitude = 51.50744999, longitude = -0.12784999)

        assertNotNull(first)
        assertNotNull(second)
        assertEquals(51.5074, first!!.latitude, 0.0)
        assertEquals(-0.1278, first.longitude, 0.0)
        assertEquals("51.5074,-0.1278", first.cacheKey)
        assertEquals(first.cacheKey, second!!.cacheKey)
    }

    @Test
    fun roundingIsHalfUpAtTheFifthDecimal() {
        val coordinates = WeatherCoordinates.from(latitude = 51.50745, longitude = -0.12785)

        assertNotNull(coordinates)
        assertEquals("51.5075,-0.1279", coordinates!!.cacheKey)
    }

    @Test
    fun coordinatesStayWithinTheLegalRangeAndKeepTheirSign() {
        val coordinates = WeatherCoordinates.from(latitude = -33.8688, longitude = 151.2093)

        assertNotNull(coordinates)
        assertEquals("-33.8688,151.2093", coordinates!!.cacheKey)
        assertEquals("-33.8688", coordinates.latitudeText)
        assertEquals("151.2093", coordinates.longitudeText)
    }

    @Test
    fun invalidCoordinatesAreRejected() {
        val invalid = listOf(
            Double.NaN to 0.0,
            0.0 to Double.NaN,
            Double.POSITIVE_INFINITY to 0.0,
            0.0 to Double.NEGATIVE_INFINITY,
            90.0001 to 0.0,
            -90.0001 to 0.0,
            0.0 to 180.0001,
            0.0 to -180.0001,
        )

        invalid.forEach { (latitude, longitude) ->
            assertNull(
                "$latitude,$longitude must be rejected",
                WeatherCoordinates.from(latitude = latitude, longitude = longitude),
            )
        }
    }

    @Test
    fun zeroAndNegativeZeroProduceOneStableKey() {
        val positive = WeatherCoordinates.from(latitude = 0.0, longitude = 0.0)
        val negative = WeatherCoordinates.from(latitude = -0.0, longitude = -0.0)

        assertNotNull(positive)
        assertNotNull(negative)
        assertEquals("0.0000,0.0000", positive!!.cacheKey)
        assertEquals(positive.cacheKey, negative!!.cacheKey)
    }
}
