import GfxMath

open class DrawingContext {
  public let backend: DrawingBackend 

  public private(set) var inherentTransforms: [DTransform2] = []
  public private(set) var inherentOpacity: Double = 1
  public private(set) var inherentClip: DRect?
  private var transforms: [DTransform2] = []
  public var opacity: Double = 1 {
    willSet {
      checkFailOpacity(newValue)
    }
  }
  private var currentClip: DRect?
  public var mergedTransforms: [DTransform2] {
    inherentTransforms + transforms
  }
  public var mergedOpacity: Double {
    inherentOpacity * opacity
  }
  public var mergedClip: DRect? {
    if let currentClip = currentClip, let inherentClip = inherentClip {
      return currentClip.intersection(with: inherentClip)
    } 
    return currentClip ?? inherentClip
  }

  public init(backend: DrawingBackend) {
    self.backend = backend 
  }

  public func clone() -> DrawingContext {
    let result = DrawingContext(backend: backend)
    result.inherentTransforms = inherentTransforms
    result.inherentOpacity = inherentOpacity
    result.inherentClip = inherentClip
    result.transforms = transforms
    result.opacity = opacity
    result.currentClip = currentClip
    return result
  }

  open func lock() {
    self.inherentTransforms = mergedTransforms
    self.transforms = []
    self.inherentOpacity = mergedOpacity
    self.opacity = 1
    self.inherentClip = mergedClip
    self.currentClip = nil
  }

  private func checkFailOpacity(_ opacity: Double) {
    if opacity < 0 || opacity > 1 {
      fatalError("opacity must be between (including) 0 and 1")
    }
  }

  open func beginDrawing() {
    backend.activate()
    if let clip = mergedClip {
      backend.clip(rect: clip)
    } else {
      backend.resetClip()
    }
  }

  private func preprocess(_ point: DVec2) -> DVec2 {
    mergedTransforms.transform(point: point)
  }

  private func preprocess(_ size: DSize2) -> DSize2 {
    mergedTransforms.transform(size: size)
  }

  public func preprocess(_ rect: DRect) -> DRect {
    let min = preprocess(rect.min)
    let max = preprocess(rect.max)
    return DRect(min: min, max: max)
  }

  private func preprocess(_ paint: Paint) -> Paint {
    var processed = paint
    if let color = paint.color {
      processed.color = color.adjusted(alpha: UInt8(mergedOpacity * color.aFrac * 255))
    }
    if let strokeColor = paint.strokeColor {
      processed.strokeColor = strokeColor.adjusted(alpha: UInt8(mergedOpacity * strokeColor.aFrac * 255))
    }
    return processed
  }

  private func preprocess(_ paint: TextPaint) -> TextPaint {
    var processed = paint
    if let color = paint.color {
      processed.color = color.adjusted(alpha: UInt8(mergedOpacity * color.aFrac * 255))
    }
    processed.fontConfig.size = preprocess(DSize2(0, processed.fontConfig.size)).height
    return processed
  }

  /** appends transform to the list of transforms, it will be the first transform to be applied */
  public func transform(_ transform: DTransform2) {
    self.transforms.append(transform)
  }

  /** appends transforms to the list of transforms, the last transform in the list will be the first one to be applied */
  public func transform(_ transforms: [DTransform2]) {
    self.transforms.append(contentsOf: transforms)
  }

  public func clip(rect: DRect) {
    let preprocessedRect = preprocess(rect)
    if let currentClip = currentClip {
      self.currentClip = currentClip.intersection(with: preprocessedRect)
    } else {
      currentClip = preprocessedRect
    }
    backend.clip(rect: mergedClip!)
  }

  public func resetClip() {
    self.currentClip = nil
    if let mergedClip = mergedClip {
      backend.clip(rect: mergedClip)
    } else {
      backend.resetClip()
    }
  }

  public func drawLine(from start: DVec2, to end: DVec2, paint: Paint) {
    backend.drawLine(from: preprocess(start), to: preprocess(end), paint: preprocess(paint))
  }

  public func drawRect(rect: DRect, paint: Paint) {
    backend.drawRect(rect: preprocess(rect), paint: preprocess(paint))
  }

  public func drawCircle(center: DVec2, radius: Double, paint: Paint) {
    backend.drawCircle(center: preprocess(center), radius: radius, paint: paint)
  }

  open func drawRoundedRect() {

  }

  open func drawPath() {
    
  }

  /**
  // TODO: maybe the result should be a rect to also have access to the position
  */
  public func measureText(text: String, paint: TextPaint) -> DSize2 {
    backend.measureText(text: text, paint: preprocess(paint))
  }

  public func drawText(text: String, position: DVec2, paint: TextPaint) {
    backend.drawText(text: text, position: preprocess(position), paint: preprocess(paint))
  }

  open func endDrawing() {
    backend.deactivate()
  }
}