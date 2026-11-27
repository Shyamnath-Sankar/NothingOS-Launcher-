/*
 * Copyright 2021, Lawnchair
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

fun getSteps(valueRange: ClosedFloatingPointRange<Float>, step: Float): Int {
    if (step == 0f) return 0
    val start = valueRange.start.toBigDecimal()
    val end = valueRange.endInclusive.toBigDecimal()
    val decimalSteps = (end - start) / step.toBigDecimal()
    val steps = decimalSteps.toInt()
    require(decimalSteps.compareTo(steps.toBigDecimal()) == 0) {
        "value range must be a multiple of step"
    }
    return steps - 1
}

fun snapSliderValue(start: Float, value: Float, step: Float): Float {
    if (step == 0f) return value
    val distance = value - start
    val stepsFromStart = (distance / step).roundToInt()
    val snappedDistance = stepsFromStart * step
    return start + snappedDistance
}
