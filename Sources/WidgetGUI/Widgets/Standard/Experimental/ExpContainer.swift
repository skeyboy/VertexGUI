import GfxMath

extension Experimental {
  public class Container: ComposedWidget, ExperimentalStylableWidget {
    private let childBuilder: SingleChildContentBuilder.ChildBuilder

    private var padding: Insets {
      stylePropertyValue(StyleKeys.padding, as: Insets.self) ?? Insets(all: 0)
    }

    override private init(contentBuilder: () -> SingleChildContentBuilder.Result) {
        let content = contentBuilder()
        self.childBuilder = content.child
        super.init()
        self.experimentalProvidedStyles.append(contentsOf: content.experimentalStyles)
    }

    public convenience init(
      classes: [String]? = nil,
      @Experimental.StylePropertiesBuilder styleProperties stylePropertiesBuilder: (StyleKeys.Type) -> Experimental.StyleProperties = { _ in [] },
      @SingleChildContentBuilder content contentBuilder: @escaping () -> SingleChildContentBuilder.Result) {
        self.init(contentBuilder: contentBuilder)
        if let classes = classes {
          self.classes = classes
        }
        self.with(stylePropertiesBuilder(StyleKeys.self))
    }

    public convenience init(
      configure: (Experimental.Container) -> (),
      @SingleChildContentBuilder content contentBuilder: @escaping () -> SingleChildContentBuilder.Result) {
        self.init(contentBuilder: contentBuilder)
        configure(self)
    }

    override public func performBuild() {
      let builtChild = childBuilder()
      rootChild = Experimental.Border(styleProperties: {
        ($0.borderWidths, stylePropertyValue(reactive: StyleKeys.borderWidths))
        ($0.borderColor, stylePropertyValue(reactive: StyleKeys.borderColor))
      }) { [unowned self] in
        Experimental.Background(styleProperties: {
          ($0.fill, stylePropertyValue(reactive: StyleKeys.backgroundFill))
        }) { 
          Experimental.ConstrainedSizeBox(styleProperties: {
            ($0.width, stylePropertyValue(reactive: StyleKeys.width))
            ($0.height, stylePropertyValue(reactive: StyleKeys.height))
          }) {
            Experimental.Padding(styleProperties: {
              ($0.insets, stylePropertyValue(reactive: StyleKeys.padding))
            }) {
              builtChild
            }
          }
        }
      }
    }

    public enum StyleKeys: String, StyleKey, ExperimentalDefaultStyleKeys {
      case width
      case height
      case padding
      case backgroundFill
      case borderWidths
      case borderColor
    }
  }
}