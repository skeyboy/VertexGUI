import GfxMath
import Foundation
import VisualAppBase
import ReactiveProperties
import CXShim

public final class TextInput: ComposedWidget, StylableWidgetProtocol
{
  @MutableBinding
  public var text: String
  private var textBuffer: String

  @ObservableProperty
  private var placeholderText: String

  @State
  private var placeholderVisibility: Visibility = .visible

  @State
  private var textTranslation: DVec2 = .zero
  /*@State
  private var caretPositionTransforms: [DTransform2]*/

  @Reference
  private var stackContainer: Container
  @Reference
  private var textWidget: Text
  @Reference
  private var caretWidget: Drawing

  @ExperimentalStyleProperty
  public var caretColor: Color = .lightBlue

  private var caretIndex: Int = 2
  private var lastDrawTimestamp: Double = 0.0
  private var caretWidth: Double = 2
  private var caretBlinkDuration: Double = 0.9
  private var caretBlinkTime = 0.0 {
    didSet {
      caretBlinkTime = caretBlinkTime.truncatingRemainder(dividingBy: caretBlinkDuration)
    }
  }
  private var caretBlinkProgress: Double {
    let raw = caretBlinkTime / caretBlinkDuration
    if raw < 0.3 {
      return 1 - raw / 0.3
    } else if raw < 0.8 {
      return (raw - 0.3) / 0.5
    } else {
      return 1
    }
  }

  private var dropCursorRequest: (() -> ())? = nil

  private var textSubscription: AnyCancellable?

  public init(
    text textBinding: MutableBinding<String>,
    placeholder: String = "") {
        
      self._text = textBinding
      self.textBuffer = textBinding.value

      super.init()

      self.$placeholderText.bind(StaticProperty(placeholder))
      updatePlaceholderVisibility()

      textSubscription = self._text.sink { [unowned self] in
        textBuffer = $0
        updatePlaceholderVisibility()
      }

      _ = onKeyDown(handleKeyDown)
      _ = onTextInput(handleTextInput)
  }

  private func updatePlaceholderVisibility() {
    if text.isEmpty && placeholderVisibility == .hidden {
      placeholderVisibility = .visible
    } else if !text.isEmpty && placeholderVisibility == .visible {
      placeholderVisibility = .hidden
    }
  }

  override public func performBuild() {
    rootChild = Container().withContent { [unowned self] _ in
      Text($text.immutable).with(classes: ["text"]).experimentalWith(styleProperties: {
        (\.$transform, Experimental.ImmutableBinding($textTranslation.immutable, get: {
          [DTransform2.translate($0)]
        }))
      }).connect(ref: $textWidget)

      Text($placeholderText).with(classes: ["placeholder"]).experimentalWith(styleProperties: {
        (\.$visibility, $placeholderVisibility.immutable)
      })
      
      Drawing(draw: drawCaret).experimentalWith(styleProperties: {
        (\.$width, 0)
        (\.$height, 0)
        (\.$opacity, ImmutableBinding($focused.immutable, get: { $0 ? 1 : 0 }))
        (\.$transform, Experimental.ImmutableBinding($textTranslation.immutable, get: {
          [DTransform2.translate($0)]
        }))
      }).connect(ref: $caretWidget)
    }.connect(ref: $stackContainer).onClick { [unowned self] in
      handleClick($0)
    }
  }

  override public var experimentalStyle: Experimental.Style {
    Experimental.Style("&") {
      (\.$padding, Insets(all: 16))
      (\.$fontSize, 16)
      (\.$overflowX, .cut)
    } nested: {

      Experimental.Style("& Container", Container.self) {
        (\.$layout, AbsoluteLayout.self)
        (\.$overflowX, .cut)
      }

      Experimental.Style(".text") {
        (\.$foreground, .white)
      }

      Experimental.Style(".placeholder") {
        (\.$opacity, 0.5)
        (\.$foreground, .white)
      }
    }
  }

  override public func performLayout(constraints: BoxConstraints) -> DSize2 {
    stackContainer.layout(constraints: constraints)
    return stackContainer.layoutedSize
  }

  private func syncText() {
    text = textBuffer
  }

  private func handleClick(_ event: GUIMouseButtonClickEvent) {
    requestFocus()

    let localX = event.position.x - stackContainer.globalPosition.x - textTranslation.x
    var maxIndexBelowX = 0
    var previousSubstringSize = DSize2.zero

    for i in 0..<text.count {
      let currentSubstringSize = textWidget.measureText(String(text.prefix(i + 1)))
      let currentLetterMiddleX = previousSubstringSize.x + (currentSubstringSize.x - previousSubstringSize.x) / 2

      if localX > currentLetterMiddleX {
        maxIndexBelowX = i + 1
      } else {
        break
      }

      previousSubstringSize = currentSubstringSize
    }

    caretIndex = maxIndexBelowX
  }

  public func handleKeyDown(_ event: GUIKeyDownEvent) {
    switch event.key {
    case .Backspace:
      if caretIndex > 0 && textBuffer.count >= caretIndex {
        textBuffer.remove(
          at: textBuffer.index(textBuffer.startIndex, offsetBy: caretIndex - 1))
        caretIndex -= 1
        syncText()
        updateTextTranslation()
      }
    case .Delete:
      if caretIndex < textBuffer.count {
        textBuffer.remove(at: textBuffer.index(textBuffer.startIndex, offsetBy: caretIndex))
        syncText()
      }
    case .ArrowLeft:
      if caretIndex > 0 {
        caretIndex -= 1
        updateTextTranslation()
      }
    case .ArrowRight:
      if caretIndex < textBuffer.count {
        caretIndex += 1
        updateTextTranslation()
      }
    default:
      break
    }
  }

  public func handleTextInput(_ event: GUITextInputEvent) {
    textBuffer.insert(
      contentsOf: event.text,
      at: textBuffer.index(textBuffer.startIndex, offsetBy: caretIndex))
    caretIndex += event.text.count
    syncText()
    updateTextTranslation()
  }

  private func updateTextTranslation() {
    let caretPositionX = textWidget.measureText(String(text.prefix(caretIndex))).width
    if caretPositionX > stackContainer.layoutedSize.width {
      let nextCharX = textWidget.measureText(String(text.prefix(caretIndex + 1))).width
      let currentCharWidth = nextCharX - caretPositionX
      let extraGap = stackContainer.layoutedSize.width * 0.1
      textTranslation = DVec2(-caretPositionX + stackContainer.layoutedSize.width - currentCharWidth - extraGap, 0)
    } else if caretPositionX + textTranslation.x < 0 {
      textTranslation = DVec2(-caretPositionX, 0)
    }
  }

  public func drawCaret(_ drawingContext: DrawingContext) {
    let timestamp = context.applicationTime
    caretBlinkTime += timestamp - lastDrawTimestamp
    lastDrawTimestamp = timestamp

    let caretTranslationX = textWidget.measureText(String(text.prefix(caretIndex))).width + caretWidth / 2

    drawingContext.drawLine(
      from: DVec2(caretTranslationX, 0),
      to: DVec2(caretTranslationX, textWidget.layoutedSize.height),
      paint: Paint(strokeWidth: caretWidth, strokeColor: caretColor.adjusted(alpha: UInt8(caretBlinkProgress * 255))))
  }

  override public func destroySelf() {
    if let drop = dropCursorRequest {
      drop()
    }
  }

  public enum StyleKeys: String, StyleKey, DefaultStyleKeys {
    case caretColor
  }
}