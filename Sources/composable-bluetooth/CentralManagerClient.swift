
import Dependencies
import CoreBluetooth
import Foundation

struct Filter {
    let services: [CBUUID] = []
    let options: [String : Any]? = nil
}

extension CBUUID {
    func toUuid() -> UUID? {
        let str: String
        if uuidString.count <= 8 {
            let padCount = max(0, 8 - uuidString.count)
            let prefix = String(repeating: "0", count: padCount)
            str = prefix + uuidString + "-0000-1000-8000-00805F9B34FB"
        } else {
            str = uuidString
        }
        return UUID(uuidString: str)
    }
}

//enum BluetoothDevice {
//    case connected(ConnectedDevice)
//    case disconnected(DisconnectedDevice)
//}
//
//extension BluetoothDevice: Equatable, Identifiable {
//    var id: UUID {
//        switch self {
//        case let .connected(device):
//            device.id
//        case let .disconnected(device):
//            device.id
//        }
//    }
//}

struct BluetoothDevice {

    let peripheral: Peripheral

    init(_ peripheral: PeripheralProtocol) {
        self.peripheral = Peripheral(peripheral)
    }
}

extension BluetoothDevice: Equatable, Identifiable {
    var id: UUID { peripheral.identifier }
}

struct CentralManagerClient {
    var enable: @Sendable () -> CBManagerState
    var disable: @Sendable () -> Void
    var getState: @Sendable () -> AsyncStream<CBManagerState>
    var startScanning: @Sendable (Filter) -> AsyncStream<Advertisement>
    var stopScanning: @Sendable (Advertisement?) -> BluetoothDevice?

    var connectDevice: @Sendable (BluetoothDevice) async -> Void
}

//extension DependencyValues {
//    var centralManagerClient: CentralManagerClient {
//        get { self[CentralManagerClient.self] }
//        set { self[CentralManagerClient.self] = newValue }
//    }
//}

extension CentralManagerClient: TestDependencyKey {
    static var testValue: CentralManagerClient {
        Self(
            enable: { .poweredOff },
            disable: { },
            getState: {
                AsyncStream<CBManagerState> { continuation in
                    continuation.finish()
                }
            },
            startScanning: { _ in
                AsyncStream<Advertisement> { continuation in
                    continuation.finish()
                }
            },
            stopScanning: { _ in nil },
            connectDevice: { _ in }
        )
    }
}
//
//extension CentralManagerClient: DependencyKey {
//    static var liveValue: CentralManagerClient {
//        let manager = BluetoothManager()
//        let stateContinuation = ContinuationHolder<CBManagerState>()
//        let advertisementContinuation = ContinuationHolder<Advertisement>()
//        let discoveredPeripherals = ReferenceTo<[UUID:CBPeripheral]>()
//        return Self(
//            enable: {
//                manager.enable()
//            },
//            disable: {
//                manager.disable()
//                stateContinuation.finish()
//                advertisementContinuation.finish()
//                discoveredPeripherals.value = nil
//            },
//            getState: {
//                AsyncStream { continuation in
//                    stateContinuation.value = continuation
//                    manager.delegate.didUpdateState = { continuation.yield($0) }
//                }
//            },
//            startScanning: { filter in
//                discoveredPeripherals.value = nil
//                manager.manager?.scanForPeripherals(withServices: filter.services, options: filter.options)
//                return AsyncStream { continuation in
//                    advertisementContinuation.value = continuation
//                    manager.delegate.didDiscover = { peripheral, advertisement in
//                        discoveredPeripherals.value?[peripheral.identifier] = peripheral
//                        continuation.yield(advertisement)
//                    }
//                }
//            },
//            stopScanning: { advertisement in
//                manager.delegate.didDiscover = nil
//                manager.manager?.stopScan()
//                advertisementContinuation.finish()
//                let peripheral = advertisement.flatMap { discoveredPeripherals.value?[$0.uuid] }
//                discoveredPeripherals.value = nil
//                return peripheral.map(BluetoothDevice.init)
//            }
//        )
//    }
//}
//
//private class ReferenceTo<T> {
//    var value: T? = nil
//}
//
//private class ContinuationHolder<T>: ReferenceTo<AsyncStream<T>.Continuation> {
//    func finish() {
//        value?.finish()
//        value = nil
//    }
//}
//
//private class BluetoothManager {
//    let queue: DispatchQueue
//    let delegate: ManagerDelegate
//    var manager: CBCentralManager?
//
//    init() {
//        self.queue = DispatchQueue(label: "queue.ble.wow")
//        self.delegate = ManagerDelegate()
//        self.manager = nil
//    }
//
//    func enable() -> CBManagerState {
//        disable()
//        let options: [String:Any] = [
//            CBCentralManagerOptionShowPowerAlertKey: NSNumber(booleanLiteral: false)
//        ]
//        let newManager = CBCentralManager(delegate: delegate, queue: queue, options: options)
//        manager = newManager
//        return newManager.state
//    }
//
//    func disable() {
//        if let oldManager = manager {
//            oldManager.delegate = nil
//            oldManager.stopScan()
//        }
//        manager = nil
//    }
//}
//
//private class ManagerDelegate: NSObject, CBCentralManagerDelegate {
//    var didUpdateState: ((CBManagerState) -> Void)? = nil
//    var didDiscover: ((CBPeripheral, Advertisement) -> Void)? = nil
//    var didConnect: ((CBPeripheral) -> Void)? = nil
//    var didDisconnect: ((CBPeripheral, (any Error)?) -> Void)? = nil
//
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        didUpdateState?(central.state)
//    }
//
//    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        let advertisement = Advertisement(
//            uuid: peripheral.identifier,
//            name: peripheral.name,
//            rssi: RSSI.intValue,
//            data: .init(with: advertisementData)
//        )
//        didDiscover?(peripheral, advertisement)
//    }
//
//    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//        didConnect?(peripheral)
//    }
//
//    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
//        didDisconnect?(peripheral, error)
//    }
//}
//
//private class PeripheralDelegate: NSObject, CBPeripheralDelegate {
//    var didDiscoverServices: (([CBService]) -> Void)? = nil
//    var didDiscoverCharacteristics: ((CBService, [CBCharacteristic]) -> Void)? = nil
//    var didUpdateValue: ((CBCharacteristic, Data) -> Void)? = nil
//
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
//        if let error = error {
//            // TODO handle error
//            fatalError("Bad \(error.localizedDescription)")
//        } else {
//            didDiscoverServices?(peripheral.services ?? [])
//        }
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
//        if let error = error {
//            // TODO handle error
//            fatalError("Bad \(error.localizedDescription)")
//        } else {
//            didDiscoverCharacteristics?(service, service.characteristics ?? [])
//        }
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
//        if let error = error {
//            // TODO handle error
//            fatalError("Bad \(error.localizedDescription)")
//        } else {
//            didUpdateValue?(characteristic, characteristic.value ?? Data())
//        }
//    }
//}
//
//
//
//
//
