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

package app.nothingui.weather.harness

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle

/**
 * The minimal platform runner for [WeatherRuntimeHarness].
 *
 * It needs no JUnit or `androidx.test` dependency: the harness reports its own
 * named case results, and this runner only forwards them into the standard
 * `am instrument -r -w` bundle. A fully green run finishes with
 * `Activity.RESULT_OK` so the host sees `INSTRUMENTATION_CODE: -1`; any failed,
 * missing or crashed case finishes with `Activity.RESULT_CANCELED` and a stream
 * result, which the smoke parser rejects.
 */
class WeatherRuntimeInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val results = Bundle()
        try {
            val report = WeatherRuntimeHarness.run(targetContext ?: context)
            val cases = report.cases
            results.putInt("harness_version", WeatherRuntimeHarness.VERSION)
            results.putString("status", if (report.passed) STATUS_PASS else STATUS_FAIL)
            results.putInt("cases_total", cases.size)
            results.putInt("cases_passed", report.passedCount)
            results.putInt("cases_failed", report.failedCount)
            results.putInt("cases_skipped", 0)
            cases.forEach { case ->
                results.putString(
                    "caseResult.${case.name}",
                    if (case.passed) STATUS_PASS else STATUS_FAIL,
                )
                results.putString("caseDetail.${case.name}", case.detail)
            }
            if (report.passed && cases.isNotEmpty()) {
                finish(Activity.RESULT_OK, results)
            } else {
                results.putString(
                    REPORT_KEY_STREAMRESULT,
                    cases.filterNot { it.passed }
                        .joinToString(separator = "\n") { "${it.name}: ${it.detail}" }
                        .ifBlank { "the weather runtime harness reported no passing cases" },
                )
                finish(Activity.RESULT_CANCELED, results)
            }
        } catch (failure: Throwable) {
            results.putString("status", STATUS_FAIL)
            results.putString(
                REPORT_KEY_STREAMRESULT,
                "the weather runtime harness crashed: ${failure.message ?: failure}",
            )
            finish(Activity.RESULT_CANCELED, results)
        }
    }

    private companion object {
        const val STATUS_PASS = "PASS"
        const val STATUS_FAIL = "FAIL"
    }
}
