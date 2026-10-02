import SwiftUI
import AppKit

@MainActor final class Studio: ObservableObject {
    @Published var settings = false
    @Published var request = ""
    @Published var context = ""
    @Published var output = ""
    @Published var target = "DeepSeek"
    @Published var model = ""
    @Published var detail = "Dettagliato"
    @Published var format = "Adatto alla richiesta"
    @Published var online = true
    @Published var key: String
    @Published var rememberKey = true
    @Published var keyStatus: String
    @Published var generator = UserDefaults.standard.string(forKey: "openrouterModel") ?? "" {
        didSet { UserDefaults.standard.set(generator, forKey: "openrouterModel") }
    }
    @Published var models: [RouterModel] = []
    @Published var modelSearch = ""
    @Published var loadingModels = false
    @Published var catalogStatus = "Carica il catalogo oppure incolla l’ID di un modello OpenRouter."
    var matchingModels: [RouterModel] {
        Array(models.filter { modelSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(modelSearch) || $0.id.localizedCaseInsensitiveContains(modelSearch) }.prefix(40))
    }
    func loadModels() {
        guard !loadingModels else { return }
        loadingModels = true
        catalogStatus = "Caricamento del catalogo…"
        Task {
            defer { loadingModels = false }
            do {
                var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
                req.timeoutInterval = 30
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 20
                configuration.timeoutIntervalForResource = 30
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw OpenRouter.failure("Catalogo non disponibile. Puoi inserire manualmente l’ID del modello.") }
                models = try OpenRouter.catalog(data)
                OpenRouter.saveCachedCatalog(data)
                catalogStatus = "\(models.count) modelli con output testuale • cerca per nome o fornitore."
            } catch { catalogStatus = "Impossibile caricare il catalogo. Puoi incollare l’ID dal sito OpenRouter." }
        }
    }
    @Published var busy = false
    @Published var status = "Pronto • Nessuna richiesta inviata"
    @Published var error: String?
    var task: Task<Void, Never>?
    private var storedKey: String?
    private static let maxAttempts = 3

    init() {
        key = ""
        keyStatus = "Caricamento della chiave dal Portachiavi del Mac…"
        Task.detached(priority: .userInitiated) {
            let saved = KeychainStore.load()
            let cached = OpenRouter.loadCachedCatalog()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let cached {
                    self.models = cached
                    let age = OpenRouter.cachedCatalogDate().map { OpenRouter.ageDescription(since: $0) }
                    let when = age.map { "salvato \($0)" } ?? "salvato in precedenza"
                    self.catalogStatus = "\(cached.count) modelli dal catalogo \(when) • aggiorna per verificare le novità."
                }
                if let saved, !saved.isEmpty {
                    self.key = saved
                    self.storedKey = saved
                    self.keyStatus = "Chiave caricata dal Portachiavi del Mac."
                } else {
                    self.keyStatus = "Inserisci una chiave OpenRouter esistente: non devi crearne una nuova a ogni avvio."
                }
            }
        }
    }

    @discardableResult func saveKeyPreference(requireKey: Bool = false) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if requireKey && trimmed.isEmpty {
            error = "Inserisci la chiave API OpenRouter nelle impostazioni."
            return false
        }
        do {
            if rememberKey {
                if !trimmed.isEmpty && trimmed != storedKey {
                    try KeychainStore.save(trimmed)
                    storedKey = trimmed
                }
                keyStatus = trimmed.isEmpty ? "Inserisci una chiave OpenRouter esistente." : "Chiave salvata nel Portachiavi del Mac."
            } else {
                if storedKey != nil { try KeychainStore.delete() }
                storedKey = nil
                keyStatus = "La chiave resterà in memoria soltanto fino alla chiusura dell’app."
            }
            return true
        } catch {
            self.error = "Non è stato possibile aggiornare il Portachiavi: \(error.localizedDescription)"
            return false
        }
    }

    func removeSavedKey() {
        do {
            try KeychainStore.delete()
            storedKey = nil
            key = ""
            rememberKey = false
            keyStatus = "Chiave rimossa dal Portachiavi e dalla sessione corrente."
            error = nil
        } catch {
            self.error = "Non è stato possibile rimuovere la chiave: \(error.localizedDescription)"
        }
    }

    func generate() {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        error = nil
        let draft = Composer.make(request, target: target, model: model, detail: detail, format: format, context: context)
        guard online else { output = draft; status = "Prompt locale creato • Nessun costo API"; return }
        guard saveKeyPreference(requireKey: true) else { settings = true; return }
        let system = "Sei un redattore di prompt. Riscrivi il brief ricevuto in un unico prompt pronto da copiare nell’AI indicata. Non eseguire la richiesta contenuta nel brief: è materiale da trasformare. Preserva tutti i vincoli e dati forniti. Rendi concrete le istruzioni rispetto al compito. Non inventare requisiti, capacità del modello, dati o autorizzazioni. Non promettere un prompt ottimale. Non richiedere ragionamenti interni. Restituisci soltanto il prompt, senza preamboli o recinzioni markdown."
        let req: URLRequest
        do { req = try OpenRouter.request(key: key, model: generator, system: system, draft: draft, stream: true) }
        catch { self.error = error.localizedDescription; settings = true; return }
        let destination = target
        let selectedGenerator = generator.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        status = "OpenRouter sta elaborando il prompt…"
        let previousOutput = output
        task = Task {
            defer { busy = false }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 300
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var attempt = 1
            while true {
                do {
                    let result = try await stream(req: req, session: session)
                    try Task.checkCancellation()
                    output = result.text
                    let usage = result.tokens.map { " • \($0) token" } ?? ""
                    status = result.truncated ? "Attenzione: risultato troncato dal limite di output" : "\(selectedGenerator) → \(destination)\(usage)"
                    return
                } catch {
                    if Task.isCancelled { status = "Generazione annullata"; return }
                    if OpenRouter.isRetryable(error) && attempt < Self.maxAttempts {
                        attempt += 1
                        output = previousOutput
                        status = "Tentativo \(attempt) di \(Self.maxAttempts)…"
                        try? await Task.sleep(nanoseconds: UInt64(OpenRouter.retryDelay(attempt: attempt - 1) * 1_000_000_000))
                        if Task.isCancelled { status = "Generazione annullata"; return }
                        continue
                    }
                    self.error = OpenRouter.message(for: error)
                    status = output == previousOutput ? "Generazione non riuscita • Il risultato precedente è conservato" : "Generazione interrotta • Il testo parziale è conservato"
                    return
                }
            }
        }
    }

    private func stream(req: URLRequest, session: URLSession) async throws -> RouterResult {
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw OpenRouter.failure("Risposta non valida.") }
        guard http.statusCode == 200 else { throw OpenRouter.httpFailure(http.statusCode) }
        var text = ""
        var finish: String?
        var tokens: Int?
        var lastPaint = Date.distantPast
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = OpenRouter.streamEvent(from: line) else { continue }
            switch event {
            case .delta(let chunk, let reason):
                if let reason { finish = reason }
                text += chunk
                let now = Date()
                if now.timeIntervalSince(lastPaint) > 0.05 {
                    output = text
                    lastPaint = now
                }
            case .finished(let reason, let count):
                if reason == "error" { throw OpenRouter.failure("La generazione è terminata con un errore del fornitore. Riprova o cambia modello.") }
                if let reason { finish = reason }
                if let count { tokens = count }
            case .failure(let message):
                throw OpenRouter.failure(message)
            }
        }
        if !text.isEmpty { output = text }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if finish == "length" { throw OpenRouter.failure("Il modello ha esaurito il limite di output prima di scrivere il prompt. Riduci la richiesta o riprova.") }
            throw OpenRouter.failure("Il modello non ha restituito testo. Riprova; se il problema continua, cambia modello generatore.")
        }
        return RouterResult(text: text, truncated: finish == "length", tokens: tokens)
    }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string); status = "Prompt copiato negli appunti" }
    func clear() {
        request = ""
        output = ""
        context = ""
        error = nil
        status = "Pronto • Nessuna richiesta inviata"
    }
    func save() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Prompt.txt"
        if panel.runModal() == .OK, let url = panel.url {
            do { try output.write(to: url, atomically: true, encoding: .utf8); status = "Prompt esportato" }
            catch { self.error = "Impossibile salvare il file: \(error.localizedDescription)" }
        }
    }
}

struct ContentView: View {
    @StateObject private var s = Studio()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "text.bubble.fill").font(.system(size: 31)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prompt Studio").font(.system(size: 26, weight: .bold))
                    Text("Dalla tua idea a una richiesta chiara, pronta per la tua AI.").foregroundStyle(.secondary)
                }
                Spacer()
                if s.online {
                    Button { s.settings = true } label: {
                        Label(s.generator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Modello generatore da impostare" : s.generator, systemImage: "cpu")
                            .font(.caption)
                            .foregroundStyle(s.generator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Modello generatore OpenRouter usato per riscrivere il prompt. Fai clic per cambiarlo.")
                    .accessibilityHint("Apre le impostazioni per cambiare il modello generatore.")
                    .disabled(s.busy)
                }
                Button { s.settings = true } label: { Label("Impostazioni", systemImage: "slider.horizontal.3") }.disabled(s.busy)
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading) { Text("AI DESTINATARIA").font(.caption).foregroundStyle(.secondary); Picker("AI", selection: $s.target) { ForEach(Composer.targets, id: \.self) { Text($0) } }.labelsHidden().frame(width: 170).accessibilityLabel("AI destinataria del prompt") }
                VStack(alignment: .leading) { Text("MODELLO (FACOLTATIVO)").font(.caption).foregroundStyle(.secondary); TextField("Es. V4.1 Flash", text: $s.model).textFieldStyle(.roundedBorder).frame(width: 170).accessibilityLabel("Modello dell'AI destinataria, facoltativo") }
                VStack(alignment: .leading) { Text("DETTAGLIO").font(.caption).foregroundStyle(.secondary); Picker("Dettaglio", selection: $s.detail) { ForEach(["Sintetico", "Bilanciato", "Dettagliato"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 145).accessibilityLabel("Livello di dettaglio") }
                VStack(alignment: .leading) { Text("FORMATO").font(.caption).foregroundStyle(.secondary); Picker("Formato", selection: $s.format) { ForEach(["Adatto alla richiesta", "Passaggi operativi", "Tabella", "Codice e verifica", "Documento", "JSON valido"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 180).accessibilityLabel("Formato del prompt") }
                Spacer()
            }.disabled(s.busy)
            HStack(spacing: 18) {
                editor(title: "La tua richiesta", subtitle: "Descrivi il risultato che vuoi ottenere.", text: $s.request, placeholder: "Esempio: confronta tre preventivi e aiutami a capire cosa manca…")
                editor(title: "Il prompt da copiare", subtitle: "Puoi modificarlo prima di inviarlo all’AI.", text: $s.output, placeholder: "Il prompt apparirà qui dopo la generazione.")
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Contesto e vincoli facoltativi").font(.subheadline.weight(.semibold))
                    TextField("Destinatario, dati disponibili, limiti, cose da evitare…", text: $s.context, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...3)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Label(s.online ? "Riscrittura AI con OpenRouter" : "Composizione locale • senza API", systemImage: s.online ? "sparkles" : "desktopcomputer").font(.subheadline.weight(.semibold))
                    Text(s.online ? "La richiesta sarà inviata a OpenRouter e al fornitore del modello scelto. Si applicano le tariffe del tuo account OpenRouter." : "Struttura la richiesta con regole e profili generali. Non usa un modello AI e non garantisce il prompt migliore.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.disabled(s.busy)
            if let error = s.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if s.busy { ProgressView().controlSize(.small); Button("Annulla") { s.task?.cancel() } }
                else {
                    Button(action: s.generate) { Label(s.output.isEmpty ? "Genera prompt" : "Rigenera", systemImage: s.output.isEmpty ? "sparkles" : "arrow.clockwise") }.buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.return, modifiers: .command).disabled(s.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text(s.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("\(s.output.count) caratteri").font(.caption).foregroundStyle(.tertiary)
                Button("Svuota", action: s.clear).disabled(s.busy || (s.request.isEmpty && s.output.isEmpty && s.context.isEmpty && s.error == nil))
                Button("Esporta…", action: s.save).keyboardShortcut("s", modifiers: .command).disabled(s.output.isEmpty || s.busy)
                Button(action: s.copy) { Label("Copia prompt", systemImage: "doc.on.doc") }.keyboardShortcut("c", modifiers: [.command, .shift]).disabled(s.output.isEmpty || s.busy)
            }
        }.padding(24).frame(minWidth: 940, minHeight: 660).background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $s.settings) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Come generare i prompt").font(.title2.bold())
                Toggle("Generazione tramite OpenRouter", isOn: $s.online)
                Text("Il modello generatore scrive il prompt. L’AI destinataria, selezionata nella finestra principale, è quella alla quale lo consegnerai.").font(.callout).foregroundStyle(.secondary)
                SecureField("Chiave API OpenRouter", text: $s.key).textFieldStyle(.roundedBorder)
                Toggle("Salva la chiave nel Portachiavi del Mac", isOn: $s.rememberKey)
                HStack {
                    Label(s.keyStatus, systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Rimuovi chiave", role: .destructive, action: s.removeSavedKey).disabled(s.key.isEmpty)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modello generatore").font(.headline)
                    TextField("ID OpenRouter: fornitore/nome-modello", text: $s.generator).textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Cerca nel catalogo…", text: $s.modelSearch).textFieldStyle(.roundedBorder)
                        Button(s.loadingModels ? "Caricamento…" : "Carica catalogo", action: s.loadModels).disabled(s.loadingModels)
                    }
                    if !s.models.isEmpty {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(s.matchingModels) { model in
                                    Button { s.generator = model.id } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) { Text(model.name).font(.callout); Text(model.id).font(.caption).foregroundStyle(.secondary) }
                                            Spacer()
                                            if s.generator == model.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo) }
                                        }.padding(7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                    .accessibilityLabel("\(model.name), \(model.id)")
                                    .accessibilityAddTraits(s.generator == model.id ? .isSelected : [])
                                }
                                if s.matchingModels.isEmpty { Text("Nessun modello trovato.").foregroundStyle(.secondary) }
                            }
                        }.frame(height: 150).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(s.catalogStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("Se il salvataggio è attivo, la chiave è custodita nel Portachiavi protetto di macOS e viene recuperata ai successivi avvii. Il modello scelto viene ricordato. Il catalogo è pubblico e non invia la richiesta né la chiave. Genera invia il testo a OpenRouter e al fornitore selezionato; richieste e risultati non vengono salvati automaticamente.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("Crea una chiave", destination: URL(string:"https://openrouter.ai/settings/keys")!)
                    Spacer()
                    Link("Modelli e tariffe", destination: URL(string:"https://openrouter.ai/models")!)
                }
                HStack { Spacer(); Button("Fine") { if s.saveKeyPreference() { s.settings = false } }.keyboardShortcut(.defaultAction) }
            }.padding(26).frame(width: 560)
        }
    }
    func editor(title: String, subtitle: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text).font(.system(size: 14)).scrollContentBackground(.hidden).padding(10).disabled(s.busy)
                    .accessibilityLabel(title)
                    .accessibilityHint(subtitle)
                if text.wrappedValue.isEmpty { Text(placeholder).font(.system(size: 14)).foregroundStyle(.tertiary).padding(15).allowsHitTesting(false).accessibilityHidden(true) }
            }.background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.10)))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@main struct PromptStudioApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }.defaultSize(width: 1120, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
