import VertexGUI

public class SearchResultsView: ComposedWidget {
  @Inject
  private var store: TodoStore

  @Compose override public var content: ComposedContent {
    Container().with(classes: ["lists-container"]).withContent {

      Dynamic(store.$state.searchResult.publisher) {

          (self.store.state.searchResult?.filteredLists ?? []).map { list in
          Container().with(classes: ["list"]).withContent {
              self.buildListHeader(list)

            list.items.map {
                self.buildSearchResult($0)
            }
          }
        }
      }
    }
  }

  func buildListHeader(_ list: TodoListProtocol) -> Widget {
    Text(list.name).with(classes: ["list-header"])
  }

  func buildSearchResult(_ todoItem: TodoItem) -> Widget {
    TodoListItemView(todoItem).with(classes: ["list-item"])
  }

  override public var style: Style {
    Style("&") {} nested: {
      Style(".lists-container", Container.self) {
        (\.$direction, .column)
        (\.$overflowY, .scroll)
        (\.$alignContent, .stretch)
      }

      Style(".list", Container.self) {
        (\.$direction, .column)
        (\.$margin, Insets(bottom: 64))
        (\.$alignContent, .stretch)
      }

      Style(".list-header") {
        (\.$margin, Insets(bottom: 32))
        (\.$fontWeight, .bold)
        (\.$fontSize, 36.0)
      }
    }
  }
}
