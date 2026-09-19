import Foundation
import Testing
@testable import TodoNativeCore

/// Decodes any real Worker capture dropped into Fixtures/local/ (git-ignored). With no files
/// present it passes trivially. Drop a `GET /changes?since=0` response there to check real rows.
@Suite("Local Worker captures")
struct LocalCaptureTests {
    private func captureURLs() -> [URL] {
        guard let root = Bundle.module.resourceURL?.appending(path: "Fixtures/local", directoryHint: .isDirectory),
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
    }

    @Test("real /changes captures decode, map, and re-encode in the same wire shape")
    func realCapturesRoundTrip() throws {
        for url in captureURLs() {
            let response = try JSONDecoder().decode(ChangesResponse.self, from: Data(contentsOf: url))
            for original in response.items {
                let item = try original.makeItem()
                let back = TodoWireDto(item)
                #expect(back.id == original.id, "\(url.lastPathComponent): id")
                #expect(back.title == original.title)
                #expect(back.isDone == original.isDone)
                #expect(back.isDeleted == original.isDeleted)
                #expect(back.serverSeq == original.serverSeq)
                try expectSameInstant(back.createdAt, original.createdAt)
                try expectSameInstant(back.updatedAt, original.updatedAt)
                try expectSameInstant(back.dueAt, original.dueAt)
                #expect(workerAcceptsPushItem(try jsonObject(back)))
            }
        }
    }
}
