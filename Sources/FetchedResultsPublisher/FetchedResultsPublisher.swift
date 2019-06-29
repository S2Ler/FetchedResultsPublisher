import Foundation
import SwiftUI
import Combine
import CoreData

public struct FetchedResultsSection<T> {
  public let name: String?
  public let indexTitle: String?
  public let values: [T]
}

/// Sends all objects which match fetchRequest per demand.
/// First demand will be send immediately, subsequent demands will be filled when there is an update in database.
public struct FetchedResultsPublisher<FetchedValue: NSFetchRequestResult, ResultValue>: Publisher {
  public typealias Output = [FetchedResultsSection<ResultValue>]
  public typealias Failure = Error

  private let reducer: ValueReducer<FetchedValue, ResultValue>
  private let fetchRequest: NSFetchRequest<FetchedValue>
  private let managedObjectContext: NSManagedObjectContext
  private let sectionNameKeyPath: String?
  private let cacheName: String?

  public init(fetchRequest: NSFetchRequest<FetchedValue>,
              reducer: ValueReducer<FetchedValue, ResultValue>,
              managedObjectContext: NSManagedObjectContext,
              sectionNameKeyPath: String?,
              cacheName: String?) {
    self.fetchRequest = fetchRequest
    self.reducer = reducer
    self.managedObjectContext = managedObjectContext
    self.sectionNameKeyPath = sectionNameKeyPath
    self.cacheName = cacheName
  }

  public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
    let subscription = FetchedResultsSubscription(fetchRequest: fetchRequest,
                                                  reducer: reducer,
                                                  managedObjectContext: managedObjectContext,
                                                  sectionNameKeyPath: sectionNameKeyPath,
                                                  cacheName: cacheName,
                                                  receiveCompletion: subscriber.receive(completion:),
                                                  receiveValue: subscriber.receive(_:))
    subscriber.receive(subscription: subscription)
  }
}

public enum FetchedResultsError: Error {
  case cannotConvertValue(NSFetchRequestResult)
}

private class FetchedResultsSubscription<FetchedValue: NSFetchRequestResult, ResultValue>
  : NSObject,
  Subscription,
  NSFetchedResultsControllerDelegate
{
  private enum State {
    case waitingForDemand
    case observing(NSFetchedResultsController<FetchedValue>, Subscribers.Demand)
    case completed
    case cancelled
  }

  private var state: State

  private let fetchRequest: NSFetchRequest<FetchedValue>
  private let managedObjectContext: NSManagedObjectContext
  private let sectionNameKeyPath: String?
  private let cacheName: String?
  private let reducer: ValueReducer<FetchedValue, ResultValue>
  private let receiveCompletion: (Subscribers.Completion<Error>) -> Void
  private let receiveValue: ([FetchedResultsSection<ResultValue>]) -> Subscribers.Demand

  init(
    fetchRequest: NSFetchRequest<FetchedValue>,
    reducer: ValueReducer<FetchedValue, ResultValue>,
    managedObjectContext: NSManagedObjectContext,
    sectionNameKeyPath: String?,
    cacheName: String?,
    receiveCompletion: @escaping (Subscribers.Completion<Error>) -> Void,
    receiveValue: @escaping ([FetchedResultsSection<ResultValue>]) -> Subscribers.Demand)
  {
    self.state = .waitingForDemand
    self.fetchRequest = fetchRequest
    self.reducer = reducer
    self.managedObjectContext = managedObjectContext
    self.sectionNameKeyPath = sectionNameKeyPath
    self.cacheName = cacheName
    self.receiveCompletion = receiveCompletion
    self.receiveValue = receiveValue
    super.init()
  }

  func request(_ demand: Subscribers.Demand) {
    func createdFetchedResultsController() -> NSFetchedResultsController<FetchedValue> {
      NSFetchedResultsController(fetchRequest: self.fetchRequest,
                                 managedObjectContext: self.managedObjectContext,
                                 sectionNameKeyPath: self.sectionNameKeyPath,
                                 cacheName: self.cacheName)
    }

    switch state {
    case .waitingForDemand:
      guard demand > 0 else {
        return
      }
      let fetchedResultsController = createdFetchedResultsController()
      fetchedResultsController.delegate = self
      state = .observing(fetchedResultsController, demand)

      do {
        try fetchedResultsController.performFetch()
        receiveUpdatedValues()
      } catch {
        receiveCompletion(.failure(error))
      }
    case .observing(let fetchedResultsController, let currentDemand):
      state = .observing(fetchedResultsController, currentDemand + demand)
    case .completed:
      break
    case .cancelled:
      break
    }
  }

  func cancel() {
    state = .cancelled
  }

  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    guard case .observing = state else {
      return
    }
    receiveUpdatedValues()
  }

  private func receiveUpdatedValues() {
    guard case .observing(let fetchedResultsController, let demand) = state else {
      return
    }

    let additionalDemand: Subscribers.Demand
    if let sections = fetchedResultsController.sections {
      var convertedSections: [FetchedResultsSection<ResultValue>] = []
      for section in sections {
        if let sectionObjects = section.objects {
          guard let objects = sectionObjects as? [FetchedValue] else {
            preconditionFailure()
          }

          convertedSections.append(FetchedResultsSection(name: section.name,
                                                         indexTitle: section.indexTitle,
                                                         values: objects.compactMap(reducer.reduce)))
        }
        else {
          convertedSections.append(FetchedResultsSection(name: section.name,
                                                         indexTitle: section.indexTitle,
                                                         values: []))
        }
      }
      additionalDemand = receiveValue(convertedSections)
    }
    else if let fetchedValues = fetchedResultsController.fetchedObjects {
      let reducedValues = fetchedValues.compactMap(reducer.reduce)
      additionalDemand = receiveValue([FetchedResultsSection(name: nil,
                                                             indexTitle: nil,
                                                             values: reducedValues)])
    }
    else {
      additionalDemand = receiveValue([])
      assertionFailure("This codepath shouldn't be reachable. If you still reach it investigate.")
    }

    let newDemand = demand + additionalDemand - 1
    if newDemand == .none {
      fetchedResultsController.delegate = nil
      state = .waitingForDemand
    } else {
      state = .observing(fetchedResultsController, newDemand)
    }
  }

  private func receiveCompletion(_ completion: Subscribers.Completion<Error>) {
    guard case .observing = state else {
      return
    }

    state = .completed
    receiveCompletion(completion)
  }
}
