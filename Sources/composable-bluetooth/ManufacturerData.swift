import CoreBluetooth
import Foundation

struct ManufacturerData: Equatable {
    let code: UInt16
    let data: Data

    static func fromRawData(_ rawData: Data) -> ManufacturerData? {
        if rawData.count < 2 {
            return nil
        }
        let code = rawData.withUnsafeBytes { bytes in
            UInt16(littleEndian: bytes.load(as: UInt16.self))
        }
        return .init(code: code, data: rawData.dropFirst(2))
    }
}

extension ManufacturerData: CustomStringConvertible {
    var description: String {
        let codeAsString = String(format: "0x%04X", code)
        let dataAsString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "ManufacturerData(Code=\(codeAsString), Data=[\(dataAsString)])"
    }
}

struct ServiceData {
    let rawDict: [CBUUID:Data]

    static func fromRawDict(_ rawDict: [CBUUID:Data]) -> ServiceData {
        return .init(rawDict: rawDict)
    }
}

extension ServiceData: CustomStringConvertible {
    var description: String {
        return "[" + rawDict.map { uuid, data in
            let dataAsString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "ServiceData(CBUUID=\(uuid), Data=[\(dataAsString)])"
        }.joined(separator: ", ") + "]"
    }
}
