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

package app.lawnchair.ui.preferences.components.controls

import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Test

class SliderValueMathTest {

    private val playRange = 0.5f..1.5f
    private val playStep = 0.01f

    @Test
    fun playDefaultFactorDisplaysSeventySixPercent() {
        val displayed = snapSliderValue(playRange.start, 0.76f, playStep)
        assertEquals(0.76f, displayed, 0.00001f)
        assertEquals(76, (displayed * 100).roundToInt())
    }

    @Test
    fun playSliderHasOneHundredPercentagePointIntervals() {
        assertEquals(99, getSteps(playRange, playStep))
    }

    @Test
    fun playStepAndReverseKeepOnePercentagePoint() {
        val start = snapSliderValue(playRange.start, 0.76f, playStep)
        val increased = snapSliderValue(playRange.start, start + playStep, playStep)
        val restored = snapSliderValue(playRange.start, increased - playStep, playStep)
        assertEquals(0.77f, increased, 0.00001f)
        assertEquals(0.76f, restored, 0.00001f)
    }

    @Test
    fun arbitraryStoredFactorDisplaysItsActualRoundedPercent() {
        assertEquals(76, (snapSliderValue(playRange.start, 0.7634f, playStep) * 100).roundToInt())
        assertEquals(84, (snapSliderValue(playRange.start, 0.835f, playStep) * 100).roundToInt())
    }

    @Test
    fun otherControlsKeepTheirExistingSteps() {
        assertEquals(9, getSteps(0.5f..1.5f, 0.1f))
        assertEquals(80, (snapSliderValue(0.5f, 0.76f, 0.1f) * 100).roundToInt())
        assertEquals(39, getSteps(0f..2f, 0.05f))
        assertEquals(100, (snapSliderValue(0f, 1f, 0.05f) * 100).roundToInt())
    }
}
