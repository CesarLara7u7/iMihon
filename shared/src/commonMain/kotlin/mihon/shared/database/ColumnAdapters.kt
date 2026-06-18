package mihon.shared.database

import app.cash.sqldelight.ColumnAdapter
import mihon.shared.domain.model.UpdateStrategy

private const val LIST_OF_STRINGS_SEPARATOR = ", "

/** Portado de `tachiyomi.data.StringListColumnAdapter` (Mihon). */
object StringListColumnAdapter : ColumnAdapter<List<String>, String> {
    override fun decode(databaseValue: String): List<String> =
        if (databaseValue.isEmpty()) emptyList() else databaseValue.split(LIST_OF_STRINGS_SEPARATOR)

    override fun encode(value: List<String>): String =
        value.joinToString(separator = LIST_OF_STRINGS_SEPARATOR)
}

/** Portado de `tachiyomi.data.UpdateStrategyColumnAdapter` (Mihon). */
object UpdateStrategyColumnAdapter : ColumnAdapter<UpdateStrategy, Long> {
    override fun decode(databaseValue: Long): UpdateStrategy =
        UpdateStrategy.entries.getOrElse(databaseValue.toInt()) { UpdateStrategy.ALWAYS_UPDATE }

    override fun encode(value: UpdateStrategy): Long = value.ordinal.toLong()
}
