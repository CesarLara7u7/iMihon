package mihon.shared.database

import app.cash.sqldelight.db.SqlDriver

/** El driver lo provee cada plataforma (iOS: NativeSqliteDriver). */
internal expect fun createDriver(): SqlDriver

/**
 * Construye la base de datos con sus adaptadores de columnas y la siembra
 * con datos de ejemplo la primera vez. En fases posteriores el sembrado se
 * sustituye por importación de backups / sincronización con fuentes.
 */
fun createMihonDatabase(): MihonDatabase {
    val driver = createDriver()
    val database = MihonDatabase(
        driver = driver,
        mangasAdapter = Mangas.Adapter(
            genreAdapter = StringListColumnAdapter,
            update_strategyAdapter = UpdateStrategyColumnAdapter,
        ),
    )
    DatabaseSeeder.seedIfEmpty(database)
    return database
}
