import Foundation

@main struct KeychainTests {
    static func main() throws {
        let service = "it.promptstudio.mac.tests.\(UUID().uuidString)"
        let account = "temporary-test-key"
        defer { try? KeychainStore.delete(service: service, account: account) }

        precondition(KeychainStore.load(service: service, account: account) == nil)
        try KeychainStore.save("test-secret-one", service: service, account: account)
        precondition(KeychainStore.load(service: service, account: account) == "test-secret-one")
        try KeychainStore.save("test-secret-two", service: service, account: account)
        precondition(KeychainStore.load(service: service, account: account) == "test-secret-two")
        try KeychainStore.delete(service: service, account: account)
        precondition(KeychainStore.load(service: service, account: account) == nil)
        print("PASS: salvataggio, lettura, aggiornamento e rimozione nel Portachiavi macOS.")
    }
}

