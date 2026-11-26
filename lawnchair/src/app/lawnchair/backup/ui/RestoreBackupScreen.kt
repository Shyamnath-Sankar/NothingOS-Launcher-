package app.lawnchair.backup.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraphBuilder
import androidx.navigation.compose.composable
import app.lawnchair.ui.preferences.LocalIsExpandedScreen
import app.lawnchair.ui.preferences.components.layout.PreferenceGroup
import app.lawnchair.ui.preferences.components.layout.PreferenceLayout
import app.lawnchair.ui.preferences.navigation.RestoreBackup
import com.android.launcher3.R

fun NavGraphBuilder.restoreBackupGraph() {
    composable<RestoreBackup> {
        RestoreBackupScreen()
    }
}

@Composable
fun RestoreBackupScreen(
    modifier: Modifier = Modifier,
) {
    PreferenceLayout(
        label = stringResource(id = R.string.restore_backup),
        modifier = modifier,
        backArrowVisible = !LocalIsExpandedScreen.current,
    ) {
        PreferenceGroup {
            BackupUnavailableNotice()
        }
    }
}
