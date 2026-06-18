package mihon.shared.domain.repository

import mihon.shared.domain.model.Chapter
import mihon.shared.domain.model.Manga

/**
 * Contrato de la biblioteca. En fases posteriores tendrá una implementación
 * respaldada por SQLDelight (Fase 2) en lugar de los datos de ejemplo.
 */
interface LibraryRepository {
    fun getLibrary(): List<Manga>
    fun getChapters(mangaId: Long): List<Chapter>
}
