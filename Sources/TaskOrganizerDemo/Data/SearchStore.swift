import SwiftGUI

public class SearchStore: ReduxStore<SearchStore.State, SearchStore.Getters, SearchStore.Mutation, SearchStore.Action> {
  var todoStore: TodoStore

  public init(todoStore: TodoStore) {
    self.todoStore = todoStore
    super.init(initialState: State())
  }

  override public func performMutation(state: inout State, mutation: Mutation) {
    switch mutation {
    case let .setQuery(query):
      state.searchQuery = query
    case let .setResults(results):
      state.searchResults = results
    }
  }

  override public func performAction(action: Action) {
    switch action {
    case let .updateResults(query):
      commit(.setQuery(query))
      commit(.setResults(findSearchResults()))
    }
  }
}

extension SearchStore {
  public struct State {
    public var searchQuery = ""
    public var searchResults = [SearchResult]()
  }

  public class Getters: ReduxGetters<State> {

  }

  public enum Mutation {
    case setQuery(String)
    case setResults([SearchResult])
  }

  public enum Action {
    case updateResults(String)
  }

  public struct SearchResult {
    public var listId: Int
    public var itemId: Int
  }

  private func findSearchResults() -> [SearchResult] {
    var results = [SearchResult]()
    
    for list in todoStore.state.lists {
      for item in list.items {
        results.append(SearchResult(listId: list.id, itemId: item.id))
      }
    }

    return results
  }
}