
import ComposableArchitecture
import CoreBluetooth
import Foundation

//public actor BleState {
//    public var managerState: CBManagerState = .unknown
//
//    func setState(_ state: CBManagerState) {
//        managerState = state
//    }
//}
//
//public struct BleWow {
//    public let managerStates: AsyncStream<CBManagerState>
//
//    public private(set) var bleState: BleState = .init()
//
//    private let queue: DispatchQueue
//    private let manager: CBCentralManager
//
//    init() {
//        queue = .init(label: "queue.ble.wow")
//        let newDelegate = CentralManagerAsyncDelegate()
//        let options: [String:Any] = [
//            CBCentralManagerOptionShowPowerAlertKey: NSNumber(booleanLiteral: false)
//        ]
//        manager = .init(delegate: newDelegate, queue: queue, options: options)
//        managerStates = AsyncStream(CBManagerState.self) { continuation in
//            Task {
//                newDelegate.continuation = continuation
//            }
//            // OR:
//            newDelegate.continuation = continuation
//        }
//        setupDelegate(manager: manager, delegate: newDelegate)
//    }
//
//    func setupDelegate(manager: CBCentralManager, delegate: CentralManagerAsyncDelegate) {
//        queue.sync {
//            Task { [state = manager.state] in
//                await bleState.setState(state)
//            }
//            delegate.bleState = bleState
//            manager.delegate = delegate
//        }
//    }
//
//}
//
//func go() {
//    let foo = BleWow()
//
//    Task.detached {
//        for await s in foo.managerStates {
//            print("Ble state is \(s.rawValue)")
//        }
//    }
//}
//
//class CentralManagerAsyncDelegate: NSObject, CBCentralManagerDelegate {
//
//    var earlyStates: [CBManagerState] = []
//    var continuation: AsyncStream<CBManagerState>.Continuation? = nil
//
//    var actorGuy: BleWow? = nil
//
//    var bleState: BleState? = nil
//
//    deinit {
//        continuation?.finish()
//    }
//
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//            Task {
//                //await actorGuy?.setState(central.state)
//                await bleState?.setState(central.state)
//            }
//
//        if let continuation = continuation {
//            if !earlyStates.isEmpty {
//                for state in earlyStates {
//                    continuation.yield(state)
//                }
//                earlyStates.removeAll()
//            }
//            continuation.yield(central.state)
//        } else {
//            earlyStates.append(central.state)
//        }
//    }
//}


//class CentralManagerActionDelegate: NSObject, CBCentralManagerDelegate {
//
//    let sendAction: (Bluetooth.Action) -> Void
//
//    init(sendAction: @escaping (Bluetooth.Action) -> Void) {
//        self.sendAction = sendAction
//    }
//
//    func centralManagerDidUpdateState(_ central: CBCentralManager) {
//        sendAction(.managerStateChanged(central.state))
//    }
//
//    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        sendAction(.advertisementReceived(.init(
//            peripheral: peripheral,
//            data: advertisementData,
//            rssi: RSSI
//        )))
//    }
//
//    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
//        sendAction(.deviceConnected(peripheral))
//    }
//
//    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
//        sendAction(.deviceDisconnected(peripheral))
//    }
//}
//
