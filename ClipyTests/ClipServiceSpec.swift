import Quick
import Nimble
import Cocoa
import RealmSwift
@testable import Clipy

class ClipServiceSpec: QuickSpec {
    override class func spec() {

        describe("clip data text parsing") {

            it("reads text from modern pasteboard string types") {
                let pasteboard = NSPasteboard.withUniqueName()
                pasteboard.declareTypes([.utf8PlainText], owner: nil)
                pasteboard.setString("hello world", forType: .utf8PlainText)

                let data = CPYClipData(pasteboard: pasteboard, types: [.utf8PlainText])

                expect(data.stringValue) == "hello world"
                expect(data.hasMeaningfulContent) == true
            }

        }

        describe("deduplication and favorite preservation") {

            var realm: Realm!

            beforeEach {
                // Use an in-memory Realm so tests never touch the real history database
                // and never require schema migrations.
                Realm.Configuration.defaultConfiguration = Realm.Configuration(inMemoryIdentifier: "ClipServiceSpec", schemaVersion: 9)
                realm = try! Realm()
                try! realm.write {
                    realm.delete(realm.objects(CPYClip.self))
                }
            }

            afterEach {
                try! realm.write {
                    realm.delete(realm.objects(CPYClip.self))
                }
                realm = nil
            }

            it("keeps a single record when identical content is saved repeatedly") {
                let service = ClipService()
                let image = self.sampleImage()

                service.create(with: image)
                service.create(with: image)
                service.create(with: image)

                expect(realm.objects(CPYClip.self).count) == 1
            }

            it("preserves the favorite flag when the same content is copied again") {
                let service = ClipService()
                let image = self.sampleImage()

                service.create(with: image)
                guard let clip = realm.objects(CPYClip.self).first else {
                    fail("clip was not created")
                    return
                }
                let hash = clip.dataHash
                try! realm.write { clip.isFavorite = true }

                // Re-copy the same content multiple times (the reported trigger).
                service.create(with: image)
                service.create(with: image)

                let refreshed = realm.object(ofType: CPYClip.self, forPrimaryKey: hash)
                expect(refreshed) != nil
                expect(refreshed?.isFavorite) == true
                expect(realm.objects(CPYClip.self).count) == 1
            }

        }

    }

    private static func sampleImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 8).fill()
        image.unlockFocus()
        return image
    }
}
