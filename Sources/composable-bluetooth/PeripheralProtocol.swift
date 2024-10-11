import Foundation

enum PeripheralConnectionState: Equatable {
    case connected, connecting, disconnected, disconnecting, unknown
}

// A protocol to erase the underlying CBPeripheral type
// We do this because it has no initializers which makes it unusable in tests
protocol PeripheralProtocol {
    var identifier: UUID { get }
    var connectionState: PeripheralConnectionState { get }
    var name: String? { get }
}

protocol PeripheralWrapperProtocol {
    associatedtype Wrapped: PeripheralProtocol
    var value: Wrapped { get }
}

@dynamicMemberLookup
struct LivePeripheral<Wrapped: PeripheralProtocol>: PeripheralWrapperProtocol {
    let value: Wrapped

    subscript<T>(dynamicMember keyPath: KeyPath<Wrapped, T>) -> T {
        value[keyPath: keyPath]
    }
}




// Wrap PeripheralProtocol as a concrete type so we can add Equatable etc
@dynamicMemberLookup
struct Peripheral {
    let value: PeripheralProtocol

    init(_ peripheral: PeripheralProtocol) {
        self.value = peripheral
    }

    subscript<T>(dynamicMember keyPath: KeyPath<PeripheralProtocol, T>) -> T {
        value[keyPath: keyPath]
    }
}

extension Peripheral: Equatable {
    static func == (lhs: Peripheral, rhs: Peripheral) -> Bool {
        guard lhs.identifier == rhs.identifier else { return false }
        guard lhs.connectionState == rhs.connectionState else { return false }
        guard lhs.name == rhs.name else { return false }
        return true
    }
}

extension Peripheral: Identifiable {
    var id: UUID { value.identifier }
}

class FakePeripheral: PeripheralProtocol {
    let identifier: UUID
    var connectionState: PeripheralConnectionState = .disconnected
    var name: String? = nil

    init(uuid: UUID = UUID(0)) {
        self.identifier = uuid
    }
}
