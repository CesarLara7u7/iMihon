package mihon.shared.database

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.native.NativeSqliteDriver

// v2: esquema con tabla `favorites` (biblioteca local). Nombre nuevo para recrear limpio
// sin necesidad de migración desde la BD antigua (que solo tenía datos de prueba).
internal actual fun createDriver(): SqlDriver =
    NativeSqliteDriver(MihonDatabase.Schema, "mihon_v5.db")
