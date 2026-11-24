package app.lawnchair.backup

import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * Android-backed readers for the pure schema and snapshot policies in
 * [BackupArchive]. Opening a second connection never closes the process-wide
 * Room singleton.
 */
object AndroidDatabaseSnapshot {
    fun read(file: File): BackupArchive.DatabaseSnapshot {
        val database = try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (t: Throwable) {
            throw BackupArchive.ValidationException("The staged database could not be opened", t)
        }
        try {
            val integrityOk = database.rawQuery("pragma integrity_check", null).use { cursor ->
                cursor.moveToFirst() && cursor.getString(0) == "ok"
            }
            val tables = mutableSetOf<String>()
            database.rawQuery(
                "select name from sqlite_master where type = 'table' " +
                    "and name not like 'sqlite_%' and name != 'android_metadata'",
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    tables += cursor.getString(0)
                }
            }
            val columns = tables.associateWith { table -> readColumns(database, table) }
            return BackupArchive.DatabaseSnapshot(
                integrityOk = integrityOk,
                userVersion = database.version,
                tables = tables,
                columns = columns,
            )
        } finally {
            database.close()
        }
    }

    fun source(file: File): BackupArchive.DatabaseSnapshotSource =
        AndroidSnapshotSource(file)

    private fun readColumns(database: SQLiteDatabase, table: String): Set<String> {
        val quoted = "\"" + table.replace("\"", "\"\"") + "\""
        val columns = mutableSetOf<String>()
        database.rawQuery("pragma table_info($quoted)", null).use { cursor ->
            while (cursor.moveToNext()) {
                columns += cursor.getString(1)
            }
        }
        return columns
    }

    private class AndroidSnapshotSource(private val file: File) :
        BackupArchive.DatabaseSnapshotSource {

        override fun checkpoint(): BackupArchive.CheckpointResult {
            val database = openReadWrite()
            try {
                database.rawQuery("pragma wal_checkpoint(truncate)", null).use { cursor ->
                    if (!cursor.moveToFirst()) {
                        return BackupArchive.CheckpointResult(busy = 0, log = -1, checkpointed = -1)
                    }
                    return BackupArchive.CheckpointResult(
                        busy = cursor.getInt(0),
                        log = cursor.getInt(1),
                        checkpointed = cursor.getInt(2),
                    )
                }
            } catch (t: Throwable) {
                throw BackupArchive.ValidationException(
                    "Could not checkpoint the database before export",
                    t,
                )
            } finally {
                database.close()
            }
        }

        override fun walBytes(): Long {
            val wal = File(file.path + "-wal")
            return if (wal.isFile) wal.length() else 0L
        }

        override fun <T> withExclusiveWriter(block: () -> T): T {
            val database = openReadWrite()
            try {
                // IMMEDIATE in WAL mode takes the writer lock, so no other
                // writer can append frames while the main file is copied.
                database.beginTransactionNonExclusive()
                try {
                    val result = block()
                    database.setTransactionSuccessful()
                    return result
                } finally {
                    database.endTransaction()
                }
            } finally {
                database.close()
            }
        }

        override fun copyMainTo(destination: File) {
            destination.parentFile?.mkdirs()
            Files.copy(
                file.toPath(),
                destination.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
        }

        private fun openReadWrite(): SQLiteDatabase = try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
        } catch (t: Throwable) {
            throw BackupArchive.ValidationException("Could not open the database for export", t)
        }
    }
}
