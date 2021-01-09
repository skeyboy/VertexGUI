import GfxMath

extension Experimental {
  public class Container: ComposedWidget, ExperimentalStylableWidget {
    private let childBuilder: () -> ChildBuilder.Result

    private var padding: Insets {
      stylePropertyValue(StyleKeys.padding, as: Insets.self) ?? Insets(all: 0)
    }

    public init(
      classes: [String]? = nil,
      @Experimental.StylePropertiesBuilder styleProperties stylePropertiesBuilder: (StyleKeys.Type) -> [Experimental.StyleProperty],
      @ChildBuilder child childBuilder: @escaping () -> ChildBuilder.Result) {
        self.childBuilder = childBuilder
        super.init()
        if let classes = classes {
          self.classes = classes
        }
        self.experimentalDirectStyleProperties.append(contentsOf: stylePropertiesBuilder(StyleKeys.self))
    }

    public init(
      classes: [String]? = nil,
      @ChildBuilder child childBuilder: @escaping () -> ChildBuilder.Result) {
        self.childBuilder = childBuilder
        super.init()
        if let classes = classes {
          self.classes = classes
        }
    }
 
    public init(
      configure: ((Experimental.Container) -> ())? = nil,
      @ChildBuilder child childBuilder: @escaping () -> ChildBuilder.Result) {
        self.childBuilder = childBuilder
        super.init()
        if let configure = configure {
          configure(self)
        }
    }

    override public func performBuild() {
      let result = childBuilder()
      rootChild = Background() { [unowned self] in
        Experimental.Background(configure: {
          $0.with(styleProperties: {
            ($0.fill, stylePropertyValue(StyleKeys.backgroundFill) ?? Color.transparent)
          })
        }) {
          Experimental.Padding(configure: {
            $0.with(styleProperties: {
              ($0.insets, self.padding)
            })
          }) {
            result.child
          }
        }
      }
      experimentalProvidedStyles.append(contentsOf: result.experimentalStyles)
    }

    public enum StyleKeys: String, StyleKey, ExperimentalDefaultStyleKeys {
      case padding
      case backgroundFill
    }
  }
}