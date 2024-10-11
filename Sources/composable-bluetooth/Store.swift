import Combine
import ComposableArchitecture
import CoreBluetooth
import Foundation
import WKWebViewJavascriptBridge

enum JsBleBridgeAction {
    case didSelectDevice(BluetoothDevice)
}

protocol JsBleBridge {
    func send(_ action: JsBleBridgeAction)
}

struct JsBleBridgeClient {
    var send: (JsBleBridgeAction) -> Void
}

struct JsBridgeCallbacks: JsBleBridge {

    let bridge: WKWebViewJavascriptBridge

    func send(_ action: JsBleBridgeAction) {
        switch action {
        case let .didSelectDevice(device):
            bridge.call(handlerName: "onDeviceSelected", data: ["device": device])
        }
    }
}



@Reducer
struct Bluetooth {

    let bridgeClient: JsBleBridgeClient

    @Dependency(CentralManagerClient.self) var centralManagerClient

    @ObservableState
    struct State: Equatable {
        var bluetoothState: CBManagerState = .unknown
        var devices: IdentifiedArrayOf<BluetoothDevice> = []
        var advertisements: IdentifiedArrayOf<Advertisement> = []
    }

    enum Action {
        // delegate stuff
        case managerStateChanged(CBManagerState)
        case advertisementReceived(Advertisement)
        case deviceConnected(BluetoothDevice)
        case deviceDisconnected(BluetoothDevice)

        // incoming requests from web page
        case requestDevice(Filter)
        case selectDevice(Advertisement)
        case cancelDeviceRequest
        case clearAdvertisements

        case connectDevice(UUID)

        case startBluetooth
        case stopBluetooth
    }

    enum CancelID { case bleState, scan }

    var body: some Reducer<State, Action> {

        Reduce { state, action in
            switch action {
            case let .managerStateChanged(newState):
                state.bluetoothState = newState
                return .none
            case let .advertisementReceived(advertisement):
                state.advertisements.updateOrAppend(advertisement)
                return .none
            case let .deviceConnected(device):
                state.devices.updateOrAppend(device)
                return .none
            case let .deviceDisconnected(device):
                state.devices.updateOrAppend(device)
                return .none

            case .clearAdvertisements:
                state.advertisements.removeAll()
                return .none

            case let .requestDevice(filter):
                return .run { send in
                    // TODO: start a timer to cancel eventually?
                    for await advertisement in centralManagerClient.startScanning(filter) {
                        await send(.advertisementReceived(advertisement))
                    }
                    await send(.clearAdvertisements)
                }

            case let .selectDevice(advertisement):
                return .run { send in
                    if let device = centralManagerClient.stopScanning(advertisement) {
                        bridgeClient.send(.didSelectDevice(device))
                    }
                }

            case .cancelDeviceRequest:
                return .run { send in
                    let _ = centralManagerClient.stopScanning(nil)
                }

            case .startBluetooth:
                return .run { send in
                    let initialState = centralManagerClient.enable()
                    await send(.managerStateChanged(initialState))
                    for await bleState in centralManagerClient.getState() {
                        await send(.managerStateChanged(bleState))
                    }
                }

            case .stopBluetooth:
                return .run { send in
                    centralManagerClient.disable()
                    await send(.managerStateChanged(.unknown))
                }

            case let .connectDevice(uuid):
                guard let device = state.devices[id: uuid] else { return .none }
                return .run { send in
                    centralManagerClient.connectDevice(device)
                }
            }
        }
    }
}


extension JsBleBridgeClient {
    static let noop = Self(
        send: { action in
            // do nothing
        }
    )
}

extension JsBleBridgeClient {
    static func live(bridge: JsBridgeCallbacks) -> Self {
        return Self(
            send: bridge.send
        )
    }
}
