import Foundation
import PackageDescription

let package = Package(
    name: "DLSQLite"
)

#if !swift(>=4)
if let _ = ProcessInfo.processInfo.environment.index(forKey: "PRODUCE_DYLIB") {
    products.append(
        Product(
            name: "DLSQLite",
            type: .Library(.Dynamic),
            modules: ["DLSQLite"]
        )
    )
}
#endif
