import SwiftUI
import Shared

/// Gestión de categorías (estanterías): crear, renombrar, eliminar.
/// Un manga puede pertenecer a varias; aquí solo se administran las categorías en sí.
struct CategoriesManagerView: View {
    @State private var categories: [MangaCategory] = []
    @State private var newName = ""
    @State private var renaming: MangaCategory?
    @State private var renameText = ""
    @State private var settingPrivacy: MangaCategory?
    @State private var magicText = ""
    @State private var revealedWords = false
    @Environment(\.dismiss) private var dismiss

    private var trimmedNew: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            Section("Nueva categoría") {
                HStack {
                    TextField("Nombre", text: $newName)
                        .onSubmit(add)
                    Button("Añadir", action: add).disabled(trimmedNew.isEmpty)
                }
            }

            Section {
                if categories.isEmpty {
                    Text("Aún no hay categorías.").foregroundStyle(.secondary)
                } else {
                    ForEach(categories, id: \.id) { c in
                        HStack {
                            Text(c.name)
                            if !c.magicWord.isEmpty {
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(Color.mihonAccent)
                                // La palabra NO se muestra; solo "Privada" (salvo recuperación con Face ID).
                                Text(revealedWords ? "“\(c.magicWord)”" : "Privada")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(c) } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            Button { renaming = c; renameText = c.name } label: {
                                Label("Renombrar", systemImage: "pencil")
                            }.tint(.blue)
                        }
                        .swipeActions(edge: .leading) {
                            Button { settingPrivacy = c; magicText = c.magicWord } label: {
                                Label(c.magicWord.isEmpty ? "Privada" : "Palabra",
                                      systemImage: c.magicWord.isEmpty ? "lock" : "lock.rotation")
                            }.tint(.indigo)
                        }
                    }
                }
            } header: {
                Text("Categorías")
            } footer: {
                Text("Desliza ➡ para renombrar/eliminar, ⬅ para hacerla privada con una palabra mágica. "
                     + "Una categoría privada se oculta y solo aparece al escribir su palabra en el buscador.")
            }
        }
        .navigationTitle("Categorías")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !revealedWords, categories.contains(where: { !$0.magicWord.isEmpty }) {
                    Button { recoverWithFaceID() } label: { Label("Recuperar", systemImage: "faceid") }
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
        }
        .onAppear(perform: reload)
        .alert("Renombrar categoría",
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Guardar") {
                if let r = renaming { rename(r, renameText) }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        }
        .alert("Estantería privada",
               isPresented: Binding(get: { settingPrivacy != nil }, set: { if !$0 { settingPrivacy = nil } })) {
            TextField("Palabra mágica (vacía = pública)", text: $magicText)
                .textInputAutocapitalization(.never)
            Button("Guardar") {
                if let c = settingPrivacy { setMagic(c, magicText) }
                settingPrivacy = nil
            }
            Button("Cancelar", role: .cancel) { settingPrivacy = nil }
        } message: {
            Text("Con una palabra, la categoría se oculta de la biblioteca y solo reaparece al "
                 + "escribir esa palabra exacta en el buscador. Déjala vacía para hacerla pública.")
        }
    }

    private func reload() {
        categories = (try? MockData.bridgeInstance.categories()) ?? []
    }

    private func setMagic(_ c: MangaCategory, _ word: String) {
        try? MockData.bridgeInstance.setCategoryMagicWord(id: c.id, word: word.trimmingCharacters(in: .whitespaces))
        reload()
    }

    private func recoverWithFaceID() {
        Task {
            if await Biometrics.authenticate(reason: "Recuperar las palabras de tus estanterías privadas") {
                withAnimation { revealedWords = true }
            }
        }
    }

    private func add() {
        guard !trimmedNew.isEmpty else { return }
        try? MockData.bridgeInstance.createCategory(name: trimmedNew)
        newName = ""
        reload()
    }

    private func rename(_ c: MangaCategory, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        try? MockData.bridgeInstance.renameCategory(id: c.id, name: n)
        reload()
    }

    private func delete(_ c: MangaCategory) {
        try? MockData.bridgeInstance.deleteCategory(id: c.id)
        reload()
    }
}

/// Selector de categorías para un manga concreto (casillas marcadas). Permite crear al vuelo.
struct CategoryPickerSheet: View {
    let sourceId: String
    let mangaId: String

    @State private var categories: [MangaCategory] = []
    @State private var selected: Set<Int32> = []
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    private var trimmedNew: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                Section("Nueva categoría") {
                    HStack {
                        TextField("Nombre", text: $newName).onSubmit(create)
                        Button("Crear", action: create).disabled(trimmedNew.isEmpty)
                    }
                }

                Section("Categorías") {
                    if categories.isEmpty {
                        Text("Sin categorías. Crea una arriba.").foregroundStyle(.secondary)
                    } else {
                        ForEach(categories, id: \.id) { c in
                            Button { toggle(c) } label: {
                                HStack {
                                    Text(c.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selected.contains(c.id) {
                                        Image(systemName: "checkmark").foregroundStyle(Color.mihonAccent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categorías")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        categories = (try? MockData.bridgeInstance.categories()) ?? []
        let mine = (try? MockData.bridgeInstance.categoriesForManga(sourceId: sourceId, mangaId: mangaId)) ?? []
        selected = Set(mine.map { $0.id })
    }

    private func toggle(_ c: MangaCategory) {
        let isIn = selected.contains(c.id)
        try? MockData.bridgeInstance.setMangaCategory(
            sourceId: sourceId, mangaId: mangaId, categoryId: c.id, inCategory: !isIn
        )
        if isIn { selected.remove(c.id) } else { selected.insert(c.id) }
    }

    private func create() {
        guard !trimmedNew.isEmpty else { return }
        try? MockData.bridgeInstance.createCategory(name: trimmedNew)
        newName = ""
        reload()
    }
}
