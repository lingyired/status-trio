import Foundation
@testable import StatusTrioCore

struct TestIconContentPlugin: IconContentPlugin {
    let descriptor: IconContentPluginDescriptor
    var result: SourceResult<IconContentPayload> = .unavailable(.unavailable)

    func resolve(presentationID: String, context: IconContentContext) -> SourceResult<IconContentPayload> {
        result
    }
}
