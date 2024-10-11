import CoreBluetooth
import Foundation
import IdentifiedCollections

struct Advertisement: Equatable, Identifiable {
    var id: UUID { uuid }
    let uuid: UUID
    let name: String?
    let rssi: Int
    let data: AdvertisementData
}

struct AdvertisementData {
    let rawDict: [String: Any]

    init(with dict: [String: Any] = [:]) {
        rawDict = dict
    }

    var isConnectable: Bool? {
        (rawDict[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue
    }

    var localName: String? {
        rawDict[CBAdvertisementDataLocalNameKey] as? String
    }

    func manufacturerData(for code: UInt16? = nil) -> ManufacturerData? {
        (rawDict[CBAdvertisementDataManufacturerDataKey] as? Data).flatMap {
            ManufacturerData.fromRawData($0).flatMap { manufacturerData in
                if let code = code {
                    return code == manufacturerData.code ? manufacturerData : nil
                } else {
                    return manufacturerData
                }
            }
        }
    }

    var overflowServiceUUIDs: [CBUUID] {
        rawDict[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
    }

    func serviceData(for uuid: CBUUID) -> Data? {
        (rawDict[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data])?[uuid]
    }

    var serviceUUIDs: [CBUUID] {
        rawDict[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    }

    var solicitedServiceUUIDs: [CBUUID] {
        rawDict[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []
    }

    var txPowerLevel: Int? {
        (rawDict[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
    }
}

extension AdvertisementData: Equatable {
    static func == (lhs: AdvertisementData, rhs: AdvertisementData) -> Bool {
        guard lhs.isConnectable == rhs.isConnectable else { return false }
        guard lhs.localName == rhs.localName else { return false }
        guard lhs.overflowServiceUUIDs == rhs.overflowServiceUUIDs else { return false }
        guard lhs.serviceUUIDs == rhs.serviceUUIDs else { return false }
        guard lhs.solicitedServiceUUIDs == rhs.solicitedServiceUUIDs else { return false }
        guard lhs.txPowerLevel == rhs.txPowerLevel else { return false }
        guard lhs.manufacturerData() == rhs.manufacturerData() else { return false }
        let lhsServiceData = lhs.rawDict[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let rhsServiceData = rhs.rawDict[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        return lhsServiceData == rhsServiceData
    }
}
