import Foundation

extension Data {

    static func fromAnyBase64(_ s: String) -> Data? {
        // Try normal base64 first
        if let d = Data(base64Encoded: s) { return d }

        // base64url -> base64
        var t = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let pad = (4 - (t.count % 4)) % 4
        if pad != 0 { t += String(repeating: "=", count: pad) }

        return Data(base64Encoded: t)
    }
}
