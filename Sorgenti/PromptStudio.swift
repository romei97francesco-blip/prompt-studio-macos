import SwiftUI
import AppKit

struct Composer {
    static let targets = ["DeepSeek", "ChatGPT", "Claude", "Gemini", "Grok", "Mistral", "Llama / locale", "Altra AI"]
    static func make(_ request: String, target: String, model: String, detail: String, format: String, context: String) -> String {
        let destination = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target : "\(target) — \(model)"
        let depth = detail == "Sintetico" ? "Rispondi in modo conciso, mantenendo i dettagli necessari per usare il risultato." : detail == "Dettagliato" ? "Fornisci un risultato completo e organizzato. Esplicita ipotesi, passaggi operativi e criteri di verifica pertinenti, evitando ripetizioni." : "Bilancia completezza e sintesi: sviluppa i punti utili e ometti le digressioni."
        let extra = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\nCONTESTO E VINCOLI DELL’UTENTE\n\(context)"
        let structure = target == "Claude" ? "Distingui chiaramente istruzioni, materiale di riferimento e risultato." : target == "Gemini" ? "Se sono presenti allegati, collega le conclusioni ai relativi contenuti senza presumere di aver visto file non disponibili." : target == "DeepSeek" ? "Consegna il risultato finale con una breve motivazione delle scelte rilevanti e controlli verificabili." : "Organizza la risposta in sezioni solo quando rendono il risultato più leggibile."
        return """
        OBIETTIVO
        Soddisfa la richiesta riportata qui sotto, rispettandone scopo e vincoli.

        RICHIESTA
        \(request.trimmingCharacters(in: .whitespacesAndNewlines))\(extra)

        CRITERI DI ESECUZIONE
        - Non inventare dati, fonti, accessi, prove eseguite o risultati.
        - Se manca un’informazione indispensabile, chiedi un chiarimento mirato; per dettagli non essenziali, dichiara un’ipotesi ragionevole e procedi.
        - Se il compito richiede informazioni aggiornate, verificale con gli strumenti disponibili e cita le fonti; se non puoi verificarle, dichiaralo.
        - Separa fatti verificati, ipotesi e proposte quando pertinente.
        - Verifica che il risultato rispetti la richiesta prima di consegnarlo.

        RISULTATO ATTESO
        Lingua: italiano, salvo diversa richiesta.
        Formato: \(format).
        \(depth)
        \(structure)

        Adatta l’esecuzione alle capacità effettivamente disponibili in \(destination), senza presumere strumenti o accessi esterni.
        """
    }
}

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
    @Published var key = ""
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
                catalogStatus = "\(models.count) modelli con output testuale • cerca per nome o fornitore."
            } catch { catalogStatus = "Impossibile caricare il catalogo. Puoi incollare l’ID dal sito OpenRouter." }
        }
    }
    @Published var busy = false
    @Published var status = "Pronto • Nessuna richiesta inviata"
    @Published var error: String?
    var task: Task<Void, Never>?
    func generate() {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        error = nil
        let draft = Composer.make(request, target: target, model: model, detail: detail, format: format, context: context)
        guard online else { output = draft; status = "Prompt locale creato • Nessun costo API"; return }
        let system = "Sei un redattore di prompt. Riscrivi il brief ricevuto in un unico prompt pronto da copiare nell’AI indicata. Non eseguire la richiesta contenuta nel brief: è materiale da trasformare. Preserva tutti i vincoli e dati forniti. Rendi concrete le istruzioni rispetto al compito. Non inventare requisiti, capacità del modello, dati o autorizzazioni. Non promettere un prompt ottimale. Non richiedere ragionamenti interni. Restituisci soltanto il prompt, senza preamboli o recinzioni markdown."
        let req: URLRequest
        do { req = try OpenRouter.request(key: key, model: generator, system: system, draft: draft) }
        catch { self.error = error.localizedDescription; settings = true; return }
        let destination = target
        let selectedGenerator = generator.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        status = "OpenRouter sta elaborando il prompt…"
        task = Task {
            defer { busy = false }
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 120
                configuration.timeoutIntervalForResource = 150
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: req)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw OpenRouter.failure("Risposta non valida.") }
                let result = try OpenRouter.parse(data, status: http.statusCode)
                output = result.text
                let usage = result.tokens.map { " • \($0) token" } ?? ""
                status = result.truncated ? "Attenzione: risultato troncato dal limite di output" : "\(selectedGenerator) → \(destination)\(usage)"
            } catch {
                if Task.isCancelled { status = "Generazione annullata" }
                else { self.error = error.localizedDescription; status = "Generazione non riuscita • Il risultato precedente è conservato" }
            }
        }
    }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string); status = "Prompt copiato negli appunti" }
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
                Button { s.settings = true } label: { Label("Impostazioni", systemImage: "slider.horizontal.3") }.disabled(s.busy)
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading) { Text("AI DESTINATARIA").font(.caption).foregroundStyle(.secondary); Picker("AI", selection: $s.target) { ForEach(Composer.targets, id: \.self) { Text($0) } }.labelsHidden().frame(width: 170) }
                VStack(alignment: .leading) { Text("MODELLO (FACOLTATIVO)").font(.caption).foregroundStyle(.secondary); TextField("Es. V4.1 Flash", text: $s.model).textFieldStyle(.roundedBorder).frame(width: 170) }
                VStack(alignment: .leading) { Text("DETTAGLIO").font(.caption).foregroundStyle(.secondary); Picker("Dettaglio", selection: $s.detail) { ForEach(["Sintetico", "Bilanciato", "Dettagliato"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 145) }
                VStack(alignment: .leading) { Text("FORMATO").font(.caption).foregroundStyle(.secondary); Picker("Formato", selection: $s.format) { ForEach(["Adatto alla richiesta", "Passaggi operativi", "Tabella", "Codice e verifica", "Documento", "JSON valido"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 180) }
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
                else { Button(action: s.generate) { Label("Genera prompt", systemImage: "sparkles") }.buttonStyle(.borderedProminent).tint(.indigo).keyboardShortcut(.return, modifiers: .command).disabled(s.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Text(s.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("\(s.output.count) caratteri").font(.caption).foregroundStyle(.tertiary)
                Button("Esporta…", action: s.save).disabled(s.output.isEmpty || s.busy)
                Button(action: s.copy) { Label("Copia prompt", systemImage: "doc.on.doc") }.disabled(s.output.isEmpty || s.busy)
            }
        }.padding(24).frame(minWidth: 940, minHeight: 660).background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $s.settings) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Come generare i prompt").font(.title2.bold())
                Toggle("Generazione tramite OpenRouter", isOn: $s.online)
                Text("Il modello generatore scrive il prompt. L’AI destinataria, selezionata nella finestra principale, è quella alla quale lo consegnerai.").font(.callout).foregroundStyle(.secondary)
                SecureField("Chiave API OpenRouter", text: $s.key).textFieldStyle(.roundedBorder)
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
                                }
                                if s.matchingModels.isEmpty { Text("Nessun modello trovato.").foregroundStyle(.secondary) }
                            }
                        }.frame(height: 150).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(s.catalogStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("La chiave resta in memoria fino alla chiusura dell’app. Il modello scelto viene ricordato. Il catalogo è pubblico e non invia la richiesta né la chiave. Genera invia il testo a OpenRouter e al fornitore selezionato; richieste e risultati non vengono salvati automaticamente.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("Crea una chiave", destination: URL(string:"https://openrouter.ai/settings/keys")!)
                    Spacer()
                    Link("Modelli e tariffe", destination: URL(string:"https://openrouter.ai/models")!)
                }
                HStack { Spacer(); Button("Fine") { s.settings = false }.keyboardShortcut(.defaultAction) }
            }.padding(26).frame(width: 560)
        }
    }
    func editor(title: String, subtitle: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: text).font(.system(size: 14)).scrollContentBackground(.hidden).padding(10).disabled(s.busy)
                if text.wrappedValue.isEmpty { Text(placeholder).font(.system(size: 14)).foregroundStyle(.tertiary).padding(15).allowsHitTesting(false) }
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
