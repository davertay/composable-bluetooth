import ComposableArchitecture
import CoreBluetooth
import Foundation


/*
 We keep ending up in a situation where we need to kick off the peripheral discovery stuff
 and it is difficult to tie that back to the exposed Store.

 One option to explore:
 How about we create an internal/private store of bluetooth peripheral state?
 Then when a peripheral is asked to be connected, we spin up two delegates:
 1. a new sub-delegate on the manager.delegate that emits the connection events
 2. the actual peripehral delegate that emits the discovery and data events

 The events are sent directly to the store which can mutate the state of the
 known peripherals. It can also emit side-effects to the store that is exposed
 to the UI layer, and to the store that is driving the Js engine.

 I think this means that we need to make the CentralManagerClient dependency hold
 onto the bluetooth peripheral store. So it has to use public types only.

 So maybe this:

 mainFeature:
 - jsBridgeFeature(state+events for talking to js)
 - bleStateFeature(state+events for CoreBluetooth)


 */


struct WrappedPeripheral {
    let peripheral: CBPeripheral
    let delegate: PeripheralDelegate

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.delegate = PeripheralDelegate()
        self.peripheral.delegate = self.delegate
    }
}

//extension WrappedPeripheral: Identifiable {
//    var id: UUID { peripheral.identifier }
//}


@Reducer
struct BluetoothEngine {

    struct State {
        var bluetoothState: CBManagerState = .unknown
        var peripheral: PeripheralActivity.State = .init()
        var advertisements: IdentifiedArrayOf<Advertisement> = []
    }

    enum Action {
        case updateManagerState(CBManagerState)
        case advertisementReceived(Advertisement)
        case peripheralConnected(CBPeripheral)
        case peripheralDisconnected(CBPeripheral, (any Error)?)

        case peripheral(PeripheralActivity.Action)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .updateManagerState(newState):
                state.bluetoothState = newState
                return .none
            case let .advertisementReceived(advertisement):
                state.advertisements.updateOrAppend(advertisement)
                return .none
            case let .peripheralConnected(peripheral):
                return .none
            case let .peripheralDisconnected(peripheral, error):
                return .none

            case let .peripheral(.discoveredServices(peripheral, error)):
                let services = peripheral.services ?? []
                
                return .none

            case .peripheral:
                return .none
            }
        }

        Scope(state: \.peripheral, action: \.peripheral) {
            PeripheralActivity()
        }
    }

//    private func updateOrAppend(state: inout State, peripheral: CBPeripheral) -> WrappedPeripheral {
//        if let existing = state.peripherals[peripheral.identifier] {
//            guard ObjectIdentifier(existing.peripheral) != ObjectIdentifier(peripheral) else {
//                return existing
//            }
//            // Recevied a fresh underlying CBPeripheral - replace the existing one
//        }
//        let wrapped = WrappedPeripheral(peripheral: peripheral)
//        state.peripherals[peripheral.identifier] = wrapped
//        return wrapped
//    }
}



class ManagerDelegate: NSObject, CBCentralManagerDelegate {

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        statePassthrough.send(central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertisement = Advertisement(
            uuid: peripheral.identifier,
            name: peripheral.name,
            rssi: RSSI.intValue,
            data: .init(with: advertisementData)
        )
//        advertisementPassthrough.send(advertisement)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//        let container = getOrCreateContainer(peripheral)
//        connectionPassthrough.send(container)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
//        let container = getOrCreateContainer(peripheral)
//        disconnectionPassthrough.send((container, error))
    }
}


@Reducer
struct PeripheralActivity {

    let sharedDelegate = PeripheralDelegate()
    // TODO: hook the store up to the delegate

    struct State {
        var peripherals: [UUID: CBPeripheral] = [:]
    }

    enum Action {
        case discoveredServices(CBPeripheral, (any Error)?)
        case discoveredCharacteristics(CBPeripheral, CBService, [CBCharacteristic], (any Error)?)
        case updatedCharacteristic(CBPeripheral, CBCharacteristic, Data, (any Error)?)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .discoveredServices(peripheral, error):
                updateOrAppend(&state, peripheral)
                return .none
            case let .discoveredCharacteristics(peripheral, _, _, _):
                updateOrAppend(&state, peripheral)
                return .none
            case let .updatedCharacteristic(peripheral, _, _, _):
                updateOrAppend(&state, peripheral)
                return .none
            }
        }
    }

    func updateOrAppend(_ state: inout State, _ peripheral: CBPeripheral) {
        if let existing = state.peripherals[peripheral.identifier],
           ObjectIdentifier(existing) == ObjectIdentifier(peripheral) {
            return
        }
        state.peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = sharedDelegate
    }
}


class PeripheralDelegate: NSObject, CBPeripheralDelegate {
    var send: ((PeripheralActivity.Action) -> Void)? = nil

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        send?(.discoveredServices(peripheral, error))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        send?(.discoveredCharacteristics(peripheral, service, service.characteristics ?? [], error))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        send?(.updatedCharacteristic(peripheral, characteristic, characteristic.value ?? Data(), error))
    }
}

