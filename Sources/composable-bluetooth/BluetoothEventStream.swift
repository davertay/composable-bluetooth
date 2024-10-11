import CasePaths
import CoreBluetooth
import Foundation


extension CentralManagerClient {
    static var liveValue: CentralManagerClient {
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
                coordinator.scan(filter: filter).map { $0.1 }.eraseToStream()
            },
            stopScanning: { advertisement in
                //let device = advertisement.flatMap {coordinator.getDiscoveredPeripheral($0.uuid) }.map(BluetoothDevice.init)
                coordinator.stopScanning()
                return nil
            },
            connectDevice: { device in
                guard let peripheral = device.peripheral.value as? CBPeripheral else { return }
                let result = await coordinator.connect(peripheral: peripheral)
                print("Got connection result \(result)")
            }
        )
    }
}

enum PublicBluetoothEvent {
    // copy of BluetoothDelegateEvent mapped to discard/hide CoreBluetooth types?
}

enum BleError: Error {
    case CausedBy(any Error)
    case Unknown
    case Finished
}

//extension BleError: Equatable {
//    static func == (lhs: BleError, rhs: BleError) -> Bool {
//        switch (lhs, rhs) {
//        case (.none, .):
//            <#code#>
//        }
//        return false
//    }
//}


private enum BluetoothDelegateEvent {
    case managerState(CBManagerState)
    case advertisement(CBPeripheral, Advertisement)
    case connected(CBPeripheral)
    case disconnected(CBPeripheral, BleError?)
    case discoveredServices(CBPeripheral, BleError?)
    case discoveredCharacteristics(CBPeripheral, CBService, BleError?)
    case updatedCharacteristic(CBPeripheral, CBCharacteristic, BleError?)
}

// extension BluetoothDelegateEvent: Equatable { }

extension BluetoothDelegateEvent {
    var peripheral: CBPeripheral? {
        switch self {
        case .managerState(_):
                .none
        case let .advertisement(peripheral, _):
            peripheral
        case let .connected(peripheral):
            peripheral
        case let .disconnected(peripheral, _):
            peripheral
        case let .discoveredServices(peripheral, _):
            peripheral
        case let .discoveredCharacteristics(peripheral, _, _):
            peripheral
        case let .updatedCharacteristic(peripheral, _, _):
            peripheral
        }
    }
}

private class BlueoothCoordinator {
    private let queue: DispatchQueue
    private let delegate: BluetoothEventStreamDelegate
    private var manager: CBCentralManager?

    init() {
        let delegate = BluetoothEventStreamDelegate()
        self.queue = DispatchQueue(label: "queue.ble.wow")
        self.delegate = delegate
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
        // TODO: dispose peripherals?
    }

    func getState() -> AsyncStream<CBManagerState> {
        delegate.events.compactMap { event in
            guard case let .managerState(state) = event else { return .none }
            return .some(state)
        }.eraseToStream()
    }

    // MARK: - Scanning

    func scan(filter: Filter) -> AsyncStream<(CBPeripheral, Advertisement)> {
        queue.sync {
            manager?.stopScan()
            manager?.scanForPeripherals(withServices: filter.services, options: filter.options)
        }
        return delegate.events.compactMap { event in
            guard case let .advertisement(peripheral, advertisement) = event else { return .none }
            return .some((peripheral, advertisement))
        }.eraseToStream()
    }

    func stopScanning() {
        queue.sync {
            manager?.stopScan()
        }
    }

    // MARK: - Connecting

    func connect(peripheral: CBPeripheral) async -> Result<CBPeripheral, BleError> {
        queue.sync {
            manager?.connect(peripheral, options: nil)
        }
        return await takeFirstNotNil(for: peripheral) { event in
            switch event {
            case let .connected(peripheral):
                return .success(peripheral)
            case let .disconnected(peripheral, .some(error)):
                return .failure(.CausedBy(error))
            case let .disconnected(peripheral, .none):
                return .failure(.Unknown)
            default:
                return .none
            }
        }
    }

    func disconnect(peripheral: CBPeripheral) async -> Void {
        queue.sync {
            manager?.cancelPeripheralConnection(peripheral)
        }
        _ = await delegate.events.first { event in
            switch event {
            case let .disconnected(other, _):
                peripheral == other
            default:
                false
            }
        }
    }

    // MARK: - Discovery

    func discoverServices(peripheral: CBPeripheral, serviceUUIDs: [CBUUID]? = nil) async -> Result<CBPeripheral, BleError> {
        queue.sync {
            peripheral.discoverServices(serviceUUIDs)
        }
        return await takeFirstNotNil(for: peripheral) { event in
            switch event {
            case let .discoveredServices(peripheral, .none):
                return .success(peripheral)
            case let .discoveredServices(_, .some(error)):
                return .failure(.CausedBy(error))
            default:
                return .none
            }
        }
    }

    /**
     * Emits the first non-nil result, or a failure result if the stream ends without emitting a non-nil.
     */
    private func takeFirstNotNil<T>(
        for peripheral: CBPeripheral? = nil,
        _ transform: @escaping @Sendable (BluetoothDelegateEvent) async -> Result<T, BleError>?
    ) async -> Result<T, BleError> {
        return await takeFirst(or: .failure(.Finished), for: peripheral, transform)
    }

    /**
     * Emits the first non-nil value, or the finished value if the stream ends without emitting a non-nil.
     */
    private func takeFirst<T>(
        or finishedValue: T,
        for peripheral: CBPeripheral? = nil,
        _ transform: @escaping @Sendable (BluetoothDelegateEvent) async -> T?
    ) async -> T {
        return await events(for: peripheral)
            .compactMap(transform)
            .first { _ in true } ?? finishedValue
    }

    /**
     * Filter to exclude peripheral related events that do not match a specific peripheral.
     */
    private func events(for peripheral: CBPeripheral? = nil) -> AsyncFilterSequence<AsyncStream<BluetoothDelegateEvent>> {
        return delegate.events.filter { event in
            switch (peripheral, event.peripheral) {
            case let (.some(lhs), .some(rhs)):
                lhs.identifier == rhs.identifier
            default:
                true
            }
        }
    }
}

//extension AsyncStream {
//    @inlinable public func firstNotNil<ElementOfResult>(
//        _ transform: @escaping @Sendable (Self.Element) async -> ElementOfResult?
//    ) async -> ElementOfResult? {
//        return await compactMap(transform).first { _ in true }
//    }
//
//    @inlinable public func firstNotNil<ElementOfResult>(
//        or defaultValue: ElementOfResult,
//        _ transform: @escaping @Sendable (Self.Element) async -> ElementOfResult?
//    ) async -> ElementOfResult {
//        return await compactMap(transform).first { _ in true } ?? defaultValue
//    }
//}

private class BluetoothEventStreamDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private var continuation: AsyncStream<BluetoothDelegateEvent>.Continuation? = nil

    lazy var events: AsyncStream<BluetoothDelegateEvent> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }()

    deinit {
        continuation?.finish()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        continuation?.yield(.managerState(central.state))
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisement = Advertisement(
            uuid: peripheral.identifier,
            name: peripheral.name,
            rssi: RSSI.intValue,
            data: .init(with: advertisementData)
        )
        continuation?.yield(.advertisement(peripheral, advertisement))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self // weak owned
        continuation?.yield(.connected(peripheral))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        peripheral.delegate = nil
        continuation?.yield(.disconnected(peripheral, error))
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        continuation?.yield(.discoveredServices(peripheral, error))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        continuation?.yield(.discoveredCharacteristics(peripheral, service, error))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        continuation?.yield(.updatedCharacteristic(peripheral, characteristic, error))
    }
}
