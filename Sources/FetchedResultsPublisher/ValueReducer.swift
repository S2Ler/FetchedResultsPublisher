import CoreData

/// Converts an instance of NSFetchRequestResult to an instance of ResultValue
public struct ValueReducer<FetchedValue: NSFetchRequestResult, ResultValue> {
  private let reducer: (FetchedValue) -> ResultValue?

  public typealias Input = FetchedValue
  public typealias Output = ResultValue

  public init(reducer: @escaping (FetchedValue) -> ResultValue?) {
    self.reducer = reducer
  }

  public func reduce(_ fetchedValue: FetchedValue) -> ResultValue? {
    return reducer(fetchedValue)
  }
}
