import Combine
import CoreBluetooth
import Dependencies
import Foundation
import Perception


private class ReferenceTo<T> {
    var value: T? = nil
}

private class ContinuationHolder<Element>: ReferenceTo<AsyncStream<Element>.Continuation> {
    func yield(_ item: sending Element) {
        value?.yield(item)
    }

    func finish() {
        value?.finish()
        value = nil
    }
}

extension CBPeripheral: PeripheralProtocol {

    var connectionState: PeripheralConnectionState {
        switch state {
        case .disconnected: .disconnected
        case .connecting: .connecting
        case .connected: .connected
        case .disconnecting: .disconnecting
        @unknown default: .unknown
        }
    }
}

// Unclear if we need the wrapper because we can write functions like this:
func doThings(perp: some PeripheralProtocol) {
    let name = perp.name
}

// Can also do this. Same as above just older syntax.
func doMoarThings<T: PeripheralProtocol>(perp: LivePeripheral<T>) {
    let name = perp.name
}

// But probably we will need to erase the type completely like this:
@dynamicMemberLookup
struct AnyPeripheral {
    private let wrapped: PeripheralProtocol

    init(perp: some PeripheralProtocol) {
        wrapped = perp
    }

    subscript<T>(dynamicMember keyPath: KeyPath<PeripheralProtocol, T>) -> T {
        wrapped[keyPath: keyPath]
    }
}

extension PeripheralProtocol {
    func eraseToAnyPeripheral() -> AnyPeripheral {
        return AnyPeripheral(perp: self)
    }
}

extension AnyPeripheral {
    func unerase<T: PeripheralProtocol>(as: T.Type) -> T? {
        return wrapped as? T
    }
}

func doAnything(perp: AnyPeripheral) {
    let name = perp.name
}

func thing(fake: FakePeripheral, real: CBPeripheral) {
    let fakeWrapper = LivePeripheral(value: fake)
    let realWrapper = LivePeripheral(value: real)

    // invoke indirectly on the wrapper
    let name = fakeWrapper.name
    let name2 = realWrapper.name

    // invoke directly on the actual object
    doThings(perp: fake)
    doThings(perp: real)

    let anyP = real.eraseToAnyPeripheral()
    doAnything(perp: anyP)
    let name3 = anyP.name

    if let gotBack = anyP.unerase(as: CBPeripheral.self) {
        gotBack.discoverServices([])
    }
}




private class PeripheralContainer {
    let peripheral: CBPeripheral
    let delegate: PassthroughPeripheralDelegate

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.delegate = PassthroughPeripheralDelegate()
        self.peripheral.delegate = self.delegate
    }
}

private enum PeripheralEvent {
    case didConnect(PeripheralContainer)
    case didDisconnect(PeripheralContainer)
    case didDisconnectWithError(PeripheralContainer, Error)
}

extension CentralManagerClient {
    static var liveValueRelay: CentralManagerClient {
        let coordinator = BlueoothCoordinator()
        return Self(
            enable: {
                coordinator.enable()
            },
            disable: {
                coordinator.disable()
            },
            getState: {
                coordinator.getState()
            },
            startScanning: { filter in
                coordinator.scan(filter: filter)
            },
            stopScanning: { advertisement in
                let device = advertisement.flatMap {coordinator.getDiscoveredPeripheral($0.uuid) }.map(BluetoothDevice.init)
                coordinator.stopScanning()
                return device
            },
            connectDevice: { device in
                guard let peripheral = device.peripheral.value as? CBPeripheral else { return }
                coordinator.connect(peripheral: peripheral)
            }
        )
    }
}

private class BlueoothCoordinator {
    private let queue: DispatchQueue
    private let delegate: PassthroughManagerDelegate
    private let peripheralDelegate: PassthroughPeripheralDelegate
    private var manager: CBCentralManager?

    init() {
        let delegate = PassthroughManagerDelegate()
        self.queue = DispatchQueue(label: "queue.ble.wow")
        self.delegate = delegate
        self.peripheralDelegate = delegate.peripheralDelegate
        self.manager = nil
    }

    func enable() -> CBManagerState {
        return queue.sync {
            reset()
            let options: [String:Any] = [
                CBCentralManagerOptionShowPowerAlertKey: NSNumber(booleanLiteral: false)
            ]
            let newManager = CBCentralManager(delegate: delegate, queue: queue, options: options)
            manager = newManager
            return newManager.state
        }
    }

    func disable() {
        queue.sync {
            reset()
        }
    }

    private func reset() {
        if let oldManager = manager {
            oldManager.delegate = nil
            oldManager.stopScan()
        }
        manager = nil
        // TODO: dispose peripherals
    }

    func getState() -> AsyncStream<CBManagerState> {
        return delegate.managerStates.values.eraseToStream()
    }

    private func cancelScanner() {
        manager?.stopScan()
        delegate.resetDiscoveredPeripherals()
    }

    func scan(filter: Filter) -> AsyncStream<Advertisement> {
        queue.sync {
            cancelScanner()
            manager?.scanForPeripherals(withServices: filter.services, options: filter.options)
        }
        return delegate.advertisements.values.eraseToStream()
    }

    func stopScanning() {
        queue.sync {
            cancelScanner()
        }
    }

    func getDiscoveredPeripheral(_ uuid: UUID) -> CBPeripheral? {
        return queue.sync {
            delegate.getDiscoveredPeripheral(uuid)
        }
    }

    func connect(peripheral: CBPeripheral) {
        queue.sync {
            manager?.connect(peripheral, options: nil)
        }
    }

}






private class PassthroughManagerDelegate: NSObject, CBCentralManagerDelegate {

    // PassthroughSubject drops values if there are no subscribers, or its current demand is zero

    private let statePassthrough = PassthroughSubject<CBManagerState, Never>()
    var managerStates: AnyPublisher<CBManagerState, Never> {
        statePassthrough.eraseToAnyPublisher()
    }

    private let advertisementPassthrough = PassthroughSubject<Advertisement, Never>()
    var advertisements: AnyPublisher<Advertisement, Never> {
        advertisementPassthrough.eraseToAnyPublisher()
    }

    private let connectionPassthrough = PassthroughSubject<CBPeripheral, Never>()
    var connections: AnyPublisher<CBPeripheral, Never> {
        connectionPassthrough.eraseToAnyPublisher()
    }

    private let disconnectionPassthrough = PassthroughSubject<(CBPeripheral, (any Error)?), Never>()
    var disconnections: AnyPublisher<(CBPeripheral, (any Error)?), Never> {
        disconnectionPassthrough.eraseToAnyPublisher()
    }

    private var discoveredPeripherals: [UUID:CBPeripheral] = [:]

    let peripheralDelegate = PassthroughPeripheralDelegate()

    deinit {
        finish()
    }

    func finish() {
        statePassthrough.send(completion: .finished)
        advertisementPassthrough.send(completion: .finished)
        connectionPassthrough.send(completion: .finished)
        disconnectionPassthrough.send(completion: .finished)
    }

    func resetDiscoveredPeripherals() {
        discoveredPeripherals = [:]
    }

    func getDiscoveredPeripheral(_ uuid: UUID) -> CBPeripheral? {
        return discoveredPeripherals[uuid]
    }

    private func updateOrAppend(peripheral: CBPeripheral) {
        if let existing = discoveredPeripherals[peripheral.identifier],
           ObjectIdentifier(existing) == ObjectIdentifier(peripheral) {
            return
        }
        discoveredPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = peripheralDelegate
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        statePassthrough.send(central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisement = Advertisement(
            uuid: peripheral.identifier,
            name: peripheral.name,
            rssi: RSSI.intValue,
            data: .init(with: advertisementData)
        )
        updateOrAppend(peripheral: peripheral)
        advertisementPassthrough.send(advertisement)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        updateOrAppend(peripheral: peripheral)
        connectionPassthrough.send(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        updateOrAppend(peripheral: peripheral)
        disconnectionPassthrough.send((peripheral, error))
    }
}



private class PassthroughPeripheralDelegate: NSObject, CBPeripheralDelegate {

    private let discoveredServicePassthrough = PassthroughSubject<(CBPeripheral, [CBService], (any Error)?), Never>()
    var discoveredServices: AnyPublisher<(CBPeripheral, [CBService], (any Error)?), Never> {
        discoveredServicePassthrough.eraseToAnyPublisher()
    }

    private let discoveredCharacteristicPassthrough = PassthroughSubject<(CBPeripheral, CBService, [CBCharacteristic], (any Error)?), Never>()
    var discoveredCharacteristics: AnyPublisher<(CBPeripheral, CBService, [CBCharacteristic], (any Error)?), Never> {
        discoveredCharacteristicPassthrough.eraseToAnyPublisher()
    }

    private let updatedCharacteristicPassthrough = PassthroughSubject<(CBPeripheral, CBCharacteristic, Data, (any Error)?), Never>()
    var updatedCharacteristic: AnyPublisher<(CBPeripheral, CBCharacteristic, Data, (any Error)?), Never> {
        updatedCharacteristicPassthrough.eraseToAnyPublisher()
    }

    deinit {
        finish()
    }

    func finish() {
        discoveredServicePassthrough.send(completion: .finished)
        discoveredCharacteristicPassthrough.send(completion: .finished)
        updatedCharacteristicPassthrough.send(completion: .finished)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        discoveredServicePassthrough.send((peripheral, peripheral.services ?? [], error))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        discoveredCharacteristicPassthrough.send((peripheral, service, service.characteristics ?? [], error))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        updatedCharacteristicPassthrough.send((peripheral, characteristic, characteristic.value ?? Data(), error))
    }
}





//
//
//private class ManagerDelegateUsingContinuations: NSObject, CBCentralManagerDelegate {
//    var stateContinuation = ContinuationHolder<CBManagerState>()
//    var advertisementContinuation = ContinuationHolder<Advertisement>()
//    var connectedContinuation = ContinuationHolder<CBPeripheral>()
//    var disconnectedContinuation = ContinuationHolder<(CBPeripheral, (any Error)?)>()
//
//    private var discoveredPeripherals: [UUID:CBPeripheral] = [:]
//
//    deinit {
//        reset()
//    }
//
//    func reset() {
//        stateContinuation.finish()
//        advertisementContinuation.finish()
//        connectedContinuation.finish()
//        disconnectedContinuation.finish()
//    }
//
//    func resetAdvertisments() {
//        advertisementContinuation.finish()
//        discoveredPeripherals = [:]
//    }
//
//    func getDiscoveredPeripheral(_ uuid: UUID) -> CBPeripheral? {
//        return discoveredPeripherals[uuid]
//    }
//
//    // MARK: - CBCentralManagerDelegate
//
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        stateContinuation.yield(central.state)
//    }
//
//    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        let advertisement = Advertisement(
//            uuid: peripheral.identifier,
//            name: peripheral.name,
//            rssi: RSSI.intValue,
//            data: .init(with: advertisementData)
//        )
//        discoveredPeripherals[peripheral.identifier] = peripheral
//        advertisementContinuation.yield(advertisement)
//    }
//
//    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//        connectedContinuation.yield(peripheral)
//    }
//
//    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
//        disconnectedContinuation.yield((peripheral, error))
//    }
//}
//
//private class PeripheralDelegateUsingContinuations: NSObject, CBPeripheralDelegate {
//    var discoveredServicesContinuation: AsyncStream<[CBService]>.Continuation? = nil
//    var discoveredCharacteristicsContinuation: AsyncStream<(CBService, [CBCharacteristic], (any Error)?)>.Continuation? = nil
//    var updatedCharacteristicContinuation: AsyncStream<(CBCharacteristic, Data, (any Error)?)>.Continuation? = nil
//
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
//        discoveredServicesContinuation?.yield(peripheral.services ?? [])
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
//        discoveredCharacteristicsContinuation?.yield((service, service.characteristics ?? [], error))
//    }
//
//    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
//        updatedCharacteristicContinuation?.yield((characteristic, characteristic.value ?? Data(), error))
//    }
//}
//
//
//private struct Relay {
//    let cancel: () -> Void
//}
//
//private struct BluetoothRelay {
//    let managerDelegate: ManagerDelegateUsingContinuations
//    // let peripheralDelegates: [PeripheralDelegateUsingContinuations]
//
//    func allStop() {
//        managerDelegate.reset()
//    }
//
//    func relayStateChanges(_ continuation: AsyncStream<CBManagerState>.Continuation) -> Relay {
//        managerDelegate.stateContinuation.value = continuation
//        return Relay { [managerDelegate] in
//            managerDelegate.stateContinuation.value = nil
//        }
//    }
//
//    func relayAdvertisements(_ continuation: AsyncStream<Advertisement>.Continuation) -> Relay {
//        managerDelegate.advertisementContinuation.value = continuation
//        return Relay { [managerDelegate] in
//            managerDelegate.advertisementContinuation.value = nil
//        }
//    }
//
//    func relayConnections(_ continuation: AsyncStream<CBPeripheral>.Continuation) -> Relay {
//        managerDelegate.connectedContinuation.value = continuation
//        return Relay { [managerDelegate] in
//            managerDelegate.connectedContinuation.value = nil
//        }
//    }
//
//    func relayDisconnections(_ continuation: AsyncStream<(CBPeripheral, (any Error)?)>.Continuation) -> Relay {
//        managerDelegate.disconnectedContinuation.value = continuation
//        return Relay { [managerDelegate] in
//            managerDelegate.disconnectedContinuation.value = nil
//        }
//    }
//
//    //    func relayAny<T>(_ continuation: AsyncStream<T>.Continuation) -> Cancellable {
//    //        managerDelegate.attachContinuation(continuation)
//    //        return Cancellable { [managerDelegate] in
//    //            managerDelegate.detachContinuation(continuation)
//    //        }
//    //    }
//}
//
//
//
//
//
