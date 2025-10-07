import Foundation

protocol AnyAggregation: Sendable {
    func feed(_ m: Message)
    func isDone(_ m: Message) -> Bool
    func result() throws -> Any
    func wait<T>() async throws -> T
}
