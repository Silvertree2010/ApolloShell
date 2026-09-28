#if !canImport(Darwin)
import Foundation

extension String {
    init(localized key: String) {
        self = key
    }
}
#endif
