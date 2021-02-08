import Foundation
import GfxMath
import VisualAppBase
import ColorizeSwift
import ReactiveProperties
import Events

open class Widget: Bounded, Parent, Child, CustomDebugStringConvertible {
    /* identification
    ------------------------------
    */
    public var name: String {
        String(describing: type(of: self))
    }

    public static var nextId: UInt = 2
    public let id: UInt

    // TODO: is this even used?
    open var key: String?

    public var debugDescription: String {
        "\(name) \(id) \(treePath)"
    } 
    /* end identification */

    /* tree properties
    ------------------------
    anything that is related to identification, navigation, messaging, etc. in a tree
    */
    open var _context: WidgetContext?
    open var context: WidgetContext {
        // TODO: might cache _context
        get {
            if let context = _context {
                return context
            }

            if let parent = parent as? Widget {
                return parent.context
            }
            
            fatalError("tried to access context when it was not yet available")
        }

        set {
            _context = newValue
        }
    }
    private var contextOnTickHandlerRemover: (() -> ())? = nil

    @usableFromInline
    internal var inspectionBus: WidgetBus<WidgetInspectionMessage> {
        context.inspectionBus
    }
    public internal(set) var lifecycleBus = WidgetBus<WidgetLifecycleMessage>()

    weak open var parent: Parent? = nil {
        willSet {
            if unregisterAnyParentChangedHandler != nil {
                unregisterAnyParentChangedHandler!()
            }
        }

        /*didSet {
            onParentChanged.invokeHandlers(parent)
            onAnyParentChanged.invokeHandlers(parent)
            if parent != nil {
                if let childParent: Child = parent as? Child {
                    unregisterAnyParentChangedHandler = childParent.onAnyParentChanged({ [unowned self] in
                        onAnyParentChanged.invokeHandlers($0)
                    })
                }
            }
        }*/
    }
    public private(set) var treePath: TreePath = []

    // TODO: maybe switch to overriding visitChildren() approach instead of children array
    public lazy var children: [Widget] = []
    /* end tree properties */

    /* lifecycle
    ---------------------------
    */
    public private(set) var lifecycleFlags: [LifecycleFlag] = [.initialized]
    private var lifecycleMethodInvocationSignalBus: Bus<LifecycleMethodInvocationSignal> {
        context.lifecycleMethodInvocationSignalBus
    }
    private var nextLifecycleMethodInvocationIds: [LifecycleMethod: Int] = LifecycleMethod.allCases.reduce(into: [:]) {
        $0[$1] = 0
    }
    /* end lifecycle */

    @available(*, deprecated, message: "Constraints is now passed as a parameter to layout(constraints:)")
    open var constraints: BoxConstraints? = nil
    lazy open internal(set) var boxConfig = getBoxConfig()
    /// bridge boxConfig for use in @inlinable functions
    @usableFromInline internal var _boxConfig: BoxConfig {
        get {
            boxConfig
        }

        set {
            boxConfig = newValue
        }
    }

    open private(set) var size = DSize2(0, 0) {
        didSet {
            if oldValue != size {
                if mounted && layouted && !layouting && !destroyed {
                    onSizeChanged.invokeHandlers(size)
                    invalidateRenderState()
                }
            }
        }
    }

    open var width: Double {
        size.width
    }
    open var height: Double {
        size.height
    }
    
    open var position = DPoint2(0, 0) {
        didSet {
            if oldValue != position {
                invalidateRenderState(deep: true)
            }
        }
    }

    @inlinable open var x: Double {
        get {
            position.x
        }
        
        set {
            position.x = newValue
        }
    }

    @inlinable open var y: Double {
        get {
            position.y
        }
        
        set {
            position.y = newValue
        }
    }
    
    // TODO: might need to create something like layoutBounds and renderBounds (area that is invalidated on rerender request --> could be more than layoutBounds and affect outside widgets (e.g. a drop shadow that is not included in layoutBounds))
    // TODO: make size unsettable from outside when new layout approach completed
    @inlinable open var bounds: DRect {
        DRect(min: position, size: size)
    }
    
    @inlinable open var globalBounds: DRect {
        return DRect(min: globalPosition, size: bounds.size)
    }
    
    @inlinable open var globalPosition: DPoint2 {
        if parent != nil {
            return parent!.globalPosition + bounds.min
        }
        return bounds.min
    }

    public internal(set) var previousConstraints: BoxConstraints?
 
    public internal(set) var focusable = false
    public internal(set) var focused = false {
        didSet {
            onFocusChanged.invokeHandlers(focused)
        }
    }
    /// bridge focused property for use in @inlinable functions
    @usableFromInline internal var _focused: Bool {
        get {
            return focused
        }

        set {
            focused = newValue
        }
    }

    public private(set) var mounted = false
    // TODO: maybe something better
    public var layoutable: Bool {
        mounted/* && constraints != nil*/ && context != nil
    }
    public var buildInvalid = false
    public var boxConfigInvalid = false
    public private(set) var layouting = false
    public private(set) var layouted = false
    // TODO: maybe rename to boundsInvalid???
    public internal(set) var layoutInvalid = false
    public internal(set) var destroyed = false

    /* style
    -----------------
    */   
    open var classes: [String] = [] {
        didSet {
            notifySelectorChanged()
        }
    }
    public internal(set) var pseudoClasses = Set<String>()

    /** Style property support declared by the Widget instance's context. */
    public var experimentalSupportedGlobalStyleProperties: Experimental.StylePropertySupportDefinitions {
        []
    }
    /** For which globally defined properties should the lifecycle management of this Widget be done automatically.
    Example: rerendering if a color property changes. */
    public var globalPropertyKeysWithAutomaticLifecycleManagement: [StyleKey] {
        []
    }
    /** Style property support declared for this Widget instance as the child of it's parent. */
    public var experimentalSupportedParentStyleProperties: Experimental.StylePropertySupportDefinitions = []
    /** Style property support declared by this Widget instance. */
    public var experimentalSupportedStyleProperties: Experimental.StylePropertySupportDefinitions { [] }
    /** */
    public var experimentalMergedSupportedStyleProperties: Experimental.StylePropertySupportDefinitions {
            do {
                return try Experimental.StylePropertySupportDefinitions(merge: experimentalSupportedGlobalStyleProperties, 
                    experimentalSupportedParentStyleProperties, experimentalSupportedStyleProperties)
            } catch {
                fatalError("error while merging style property support definitions in Widget: \(self), error: \(error)")
            }
        }

    /** All properties from matched styles and direct properties merged,
    validated and filtered according to the support definitions.  */
    public internal(set) var experimentalAppliedStyleProperties: [Experimental.StyleProperty] = []

    /** whether this Widget creates a new scope for the children which it itself instantiates */
    public var createsStyleScope: Bool = false {
        didSet {
            if mounted {
                fatalError("tried to set createsStyleScope at the wrong time, can only set it during init")
            }
        }
    }
    /** the scope this Widget belongs to */
    public var styleScope: UInt = 0
    public static let rootStyleScope: UInt = 1
    internal private(set) static var activeStyleScope: UInt = rootStyleScope

    @discardableResult
    public static func inStyleScope<T>(_ scope: UInt, block: () -> T) -> T {
        let previousActiveStyleScope = Widget.activeStyleScope
        Widget.activeStyleScope = scope
        defer { Widget.activeStyleScope = previousActiveStyleScope }
        return block()
    }

    public var providedStyles: [AnyStyle] = []
    /** Styles which can be applied to this Widget instance or any of 
    it's children (deep) according to their selector. */
    public var experimentalProvidedStyles: [Experimental.Style] = []

    internal var appliedStyles: [AnyStyle] = []
    internal var matchedStylesInvalid = false
    /** Styles whose selectors match this Widget instance. */
    internal var experimentalMatchedStyles: [Experimental.Style] = [] {
        didSet {
            if experimentalMatchedStyles.count != oldValue.count || !experimentalMatchedStyles.allSatisfy({ style in oldValue.contains { $0 === style } }) {
                stylePropertiesResolver.styles = experimentalMatchedStyles
                stylePropertiesResolver.resolve()
            }
        }
    }
    /** Style properties that are applied to this Widget instance directly
    without any selector based testing. */
    public internal(set) var experimentalDirectStyleProperties: [Experimental.StyleProperties] = [] {
        didSet {
            stylePropertiesResolver.directProperties = experimentalDirectStyleProperties
            stylePropertiesResolver.resolve()
        }
    }

    lazy internal var stylePropertiesResolver = Experimental.StylePropertiesResolver(
        propertySupportDefinitions: experimentalMergedSupportedStyleProperties,
        widget: self)

    @FromStyle(key: Experimental.AnyDefaultStyleKeys.opacity)
    public var opacity: Double = 1

    @FromStyle(key: Experimental.AnyDefaultStyleKeys.visibility)
    public var visibility: Visibility = .visible

    @FromStyle(key: Experimental.AnyDefaultStyleKeys.overflowX)
    public var overflowX: Overflow = .show
    
    @FromStyle(key: Experimental.AnyDefaultStyleKeys.overflowY)
    public var overflowY: Overflow = .show

    // TODO: maybe this belongs into the layout section instead of in the style section?
    // TODO: maybe even create a separate section for universal properties?
    @FromStyle(key: Experimental.AnyDefaultStyleKeys.padding)
    public var padding: Insets = .zero

    @FromStyle(key: Experimental.AnyDefaultStyleKeys.borderWidth)
    public var borderWidth: BorderWidth = .zero

    @FromStyle(key: Experimental.AnyDefaultStyleKeys.borderColor)
    public var borderColor: Color = .transparent

    @FromStyle(key: Experimental.AnyDefaultStyleKeys.background)
    public var background: Color = .transparent
    /* end style */

    /* scrolling
    ------------------------------------
    */
    internal var scrollingEnabled = (x: false, y: false) {
        didSet {
            updateScrollEventHandler()
        }
    }
    private var removeScrollEventHandler: (() -> ())? = nil
    private var scrollingSpeed = 20.0
    internal var currentScrollOffset: DVec2 = .zero
    /** should be set in layout, if scrolling is enabled */
    internal var maxScrollOffset: DVec2 = .zero
    /** should be set in layout, if scrolling is enabled */
    internal var minScrollOffset: DVec2 = .zero

    internal var pseudoScrollBarX = ScrollBar()
    internal var pseudoScrollBarY = ScrollBar()
    /* end scrolling */

    @usableFromInline internal var reference: AnyReferenceProtocol? {
        didSet {
            if var reference = reference {
                reference.anyReferenced = self
            }
        }
    }

    @usableFromInline internal var renderState = RenderState()

    /// Flag whether to show bounds and sizes for debugging purposes.
    //@MutableProperty
    ////internal var _debugLayout: Bool?
    @MutableProperty
    public var debugLayout: Bool = false/* {
        get {
            _debugLayout ?? context.debugLayout
        }

        set {
            _debugLayout = newValue
        }
    }*/
    @MutableProperty
    public var layoutDebuggingColor = Color.red
    private let layoutDebuggingTextFontConfig = FontConfig(family: defaultFontFamily, size: 16, weight: .regular, style: .normal)
    // if true, highlight the Widget when bursts of calls to functions such as layout or render occur
    public var burstHighlightEnabled = true
    @usableFromInline
    internal var highlighted = false

    public var countCalls: Bool = true
    public var countCallsFlash: Bool = false
    @usableFromInline lazy internal var callCounter = CallCounter(widget: self)

    public internal(set) var onParentChanged = EventHandlerManager<Parent?>()
    public let onDependenciesInjected = WidgetEventHandlerManager<Void>()
    public internal(set) var onMounted = EventHandlerManager<Void>()
    public let onBuildInvalidated = WidgetEventHandlerManager<Void>()
    public internal(set) var onTick = WidgetEventHandlerManager<Tick>()
    public internal(set) var onBoxConfigInvalidated = WidgetEventHandlerManager<Void>()
    public internal(set) var onBoxConfigChanged = EventHandlerManager<BoxConfigChangedEvent>()
    public internal(set) var onSizeChanged = EventHandlerManager<DSize2>()
    public internal(set) var onLayoutInvalidated = EventHandlerManager<Void>()
    public internal(set) var onLayoutingStarted = EventHandlerManager<BoxConstraints>()
    public internal(set) var onLayoutingFinished = EventHandlerManager<DSize2>()
    public internal(set) var onRenderStateInvalidated = EventHandlerManager<Widget>()
    public internal(set) var onFocusChanged = WidgetEventHandlerManager<Bool>()
    public internal(set) var onDestroy = EventHandlerManager<Void>()

    /* mouse events
    --------------------------
    */
    public let onClick = WidgetEventHandlerManager<GUIMouseButtonClickEvent>()
    public let onMouseWheel = WidgetEventHandlerManager<GUIMouseWheelEvent>()
    /* end mouse events */
    
    private var unregisterAnyParentChangedHandler: EventHandlerManager<Parent?>.UnregisterCallback?
	
    public init(children: [Widget] = []) {
        self.id = Self.nextId
        Self.nextId += 1
        self.children = children
        self.styleScope = Widget.activeStyleScope

        setupWidgetEventHandlerManagers()
        setupFromStyleWrappers()

        _ = onDestroy(_debugLayout.onChanged { [unowned self] _ in
            invalidateRenderState()
        })
        _ = onDestroy(_layoutDebuggingColor.onChanged { [unowned self] _ in
            invalidateRenderState()
        })
    }

    
    /* internal widget setup / management
    -----------------------------------------------------
    */
    private func setupWidgetEventHandlerManagers() {
        let mirror = Mirror(reflecting: self)
        for child in mirror.allChildren {
            if var manager = child.value as? AnyWidgetEventHandlerManager {
                manager.widget = self
            }
        }
    }

    private func setupFromStyleWrappers() {
        let mirror = Mirror(reflecting: self)
        for child in mirror.allChildren {
            if let fromStyle = child.value as? FromStyleProtocol {
                fromStyle.registerWidget(self)
            }
        }
    }

    private func updateScrollEventHandler() {
        if let remove = removeScrollEventHandler {
            remove()
        }

        if scrollingEnabled.x || scrollingEnabled.y {
            removeScrollEventHandler = onMouseWheel.addHandler { [unowned self] event in
                processMouseWheelEventUpdateScroll(event)
            }
        }
    }

    /** Used if the widget is in scrolling mode. Updates the scroll position based on mouse wheel events. */
    private func processMouseWheelEventUpdateScroll(_ event: GUIMouseWheelEvent) {
        let enabledDimensions = DVec2(scrollingEnabled.x ? 1 : 0, scrollingEnabled.y ? 1 : 0)
        self.currentScrollOffset += event.scrollAmount * self.scrollingSpeed * enabledDimensions
        self.currentScrollOffset = min(max(self.currentScrollOffset, self.minScrollOffset), self.maxScrollOffset)

    }
    /* end internal widget setup / management */

    /** side effect: increments the stored next id for the next call of this function. */
    private func getNextLifecycleMethodInvocationId(_ method: LifecycleMethod) -> Int {
        defer { nextLifecycleMethodInvocationIds[method]! += 1 }
        return nextLifecycleMethodInvocationIds[method]!
    }

    // TODO: maybe find better names for the following functions?
    @inlinable
    public final func with(key: String) -> Self {
        self.key = key
        return self
    }

    @inlinable
    public final func connect(ref reference: AnyReferenceProtocol) -> Self {
        self.reference = reference
        self.reference!.anyReferenced = self
        return self
    }

    @inlinable
    public final func with(block: (Self) -> ()) -> Self {
        block(self)
        return self
    }

    private final func setupContext() {
        contextOnTickHandlerRemover = context.onTick({ [weak self] in
          if let self = self {
            self.onTick.invokeHandlers($0)
          } else {
            print("THERE IS NO SELF IN ON TICK!")
          }
        })
    }
    
    private final func undoContextSetup() {
      if contextOnTickHandlerRemover == nil {
        print("warn: called undoContextSetup when remove handler is nil")
      }
      if let remove = contextOnTickHandlerRemover {
        remove()
      }
    }
    
    public final func mount(
        parent: Parent,
        treePath: TreePath,
        context: WidgetContext,
        lifecycleBus: WidgetBus<WidgetLifecycleMessage>,
        with replacementContext: ReplacementContext? = nil) {
            self.context = context
            self.setupContext()
            self.lifecycleBus = lifecycleBus
            
                var oldSelf: Widget? = replacementContext?.previousWidget
                if let replacementContext = replacementContext {
                    if let newKey = self.key {
                        oldSelf = replacementContext.keyedWidgets[newKey]
                    }

                    if let newSelf = self as? (Widget & AnyStatefulWidget), let oldSelf = oldSelf as? (Widget & AnyStatefulWidget) {
                        var attemptStateReplace = false

                        if  let newKey = newSelf.key,
                            let oldKey = oldSelf.key,
                            oldKey == newKey {
                                attemptStateReplace = true
                        } else if newSelf.key == nil, oldSelf.key == nil {
                            attemptStateReplace = true
                        }

                        if attemptStateReplace && type(of: newSelf) == type(of: oldSelf) {
                            newSelf.anyState = oldSelf.anyState
                        }
                    }
                }
            
                self.parent = parent
                self.treePath = treePath

                resolveDependencies()

                onDependenciesInjected.invokeHandlers(())

                addedToParent()

                build()
        
                mounted = true

                onMounted.invokeHandlers(Void())

                invalidateMatchedStyles()
    }

    private final func resolveDependencies() {
        var injectables = [AnyInject]()
        
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.value is _AnyInject {
                injectables.append(child.value as! AnyInject)
            }
        }

        if injectables.count > 0 {
            let providers = getParents(ofType: DependencyProvider.self)
            for provider in providers {
                for var injectable in injectables {
                    if injectable.anyValue == nil {
                        if let dependency = provider.getDependency(ofType: injectable.anyType) {
                            injectable.anyValue = dependency.value
                        }
                    }
                }
            }
        }
    }

    open func addedToParent() {
    }

    // TODO: this is work in progress, possibly one step towards a new approach to child handling
    open func visitChildren() -> ChildIterator {
        ChildIterator(count: children.count) { [unowned self] in
            children[$0]
        }
    }

    // TODO: maybe rename to inMount or something like that
    public final func build() {
        // TODO: check for invalid build
        // TODO: preserve state when it is the second build / n > 0 th build

        #if DEBUG
        if countCalls {
            callCounter.count(.Build)
        }
        
        inspectionBus.publish(WidgetInspectionMessage(sender: self, content: .BuildStarted))
        #endif

        let oldChildren = children
        
        // TODO: should probably not call destroy here as these children might be mounted somewhere else, maybe have something like unmount()
        /*for oldChild in oldChildren {
            oldChild.destroy()
        }*/

        Widget.inStyleScope(self.createsStyleScope ? self.id : self.styleScope) {
            performBuild()
        }

        // TODO: should mountChildren be called by build?
        mountChildren(oldChildren: oldChildren)

        buildInvalid = false

        #if DEBUG
        inspectionBus.publish(WidgetInspectionMessage(sender: self, content: .BuildFinished))
        #endif

        invalidateBoxConfig()
        invalidateLayout()
        invalidateRenderState()
    }

    open func performBuild() {
        
    }
    
    /**
    Checks whether the state of the old children can be transferred to the new children and if yes, applies it.
    */
    private final func mountChildren(oldChildren: [Widget]) {
        var keyedChildren: [String: Widget] = [:]
        var checkChildren: [Widget] = oldChildren

        while let child = checkChildren.popLast() {
            if let key = child.key {
                keyedChildren[key] = child
            }

            checkChildren.append(contentsOf: child.children)
        }

        /* OLD CODE TAKEN OUT OF MOUNT
        // TODO: reimplement state retaining
        for i in 0..<children.count {
            let oldChild: Widget?
            if let oldSelf = oldSelf {
                oldChild = oldSelf.children.count > i ? oldSelf.children[i] : nil
            } else {
                oldChild = nil
            }

            let childContext = oldChild == nil && context == nil ? nil : ReplacementContext(
                previousWidget: oldChild, keyedWidgets: replacementContext?.keyedWidgets ?? [:])
        
            mountChild(children[i], with: childContext)
        }
        */

        for i in 0..<children.count {
            let newChild = children[i]
            let oldChild: Widget? = oldChildren.count > i ? oldChildren[i] : nil
            let childContext = ReplacementContext(previousWidget: oldChild, keyedWidgets: keyedChildren)
            mountChild(newChild, treePath: self.treePath/i, with: childContext)
        }

       /* for child in oldChildren {
            child.destroy()
        }*/
    }

    public func mountChild(_ child: Widget, treePath: TreePath, with replacementContext: ReplacementContext? = nil) {
        child.mount(parent: self, treePath: treePath, context: context, lifecycleBus: lifecycleBus, with: replacementContext)

        _ = child.onBoxConfigChanged { [unowned self, unowned child] _ in
            handleChildBoxConfigChanged(child: child)
        }

        _ = child.onSizeChanged { [unowned self, unowned child] _ in
            // TODO: maybe need special relayout flag / function
            Logger.log("Size of child \(child) of parent \(self) changed.".with(fg: .blue, style: .bold), level: .Message, context: .WidgetLayouting)
            if layouted && !layouting {
                Logger.log("Performing layout on parent parent.", level: .Message, context: .WidgetLayouting)
                invalidateLayout()
            }
        }
        
        _ = child.onFocusChanged { [weak self] in
            if let self = self {
                self.focused = $0
            }
        }
    }

    @inlinable
    public final func invalidateBuild() {
        if buildInvalid {
            #if DEBUG
            Logger.warn("Called invalidateBuild() on a Widget where build is already invalid: \(self)", context: .WidgetBuilding)
            #endif
            return
        }

        if !mounted || destroyed {
            #if DEBUG
            Logger.warn("Called invalidateBuild() on a Widget that has not yet been mounted or is already destroyed: \(self)", context: .WidgetBuilding)
            #endif
            return
        }

        _invalidateBuild()
    }

    @usableFromInline
    @inlinable
    internal final func _invalidateBuild() {
        #if DEBUG
        inspectionBus.publish(WidgetInspectionMessage(sender: self, content: .BuildInvalidated))
        #endif

        buildInvalid = true

        lifecycleBus.publish(WidgetLifecycleMessage(sender: self, content: .BuildInvalidated))
        
        #if DEBUG
        context.inspectionBus.publish(WidgetInspectionMessage(sender: self, content: .BuildInvalidated))
        #endif

        onBuildInvalidated.invokeHandlers()
    }

    private final func handleChildBoxConfigChanged(child: Widget) {
        Logger.log("Box config of child: \(child) of parent \(self) changed.".with(fg: .blue, style: .bold), level: .Message, context: .WidgetLayouting)

        if layouted && !layouting {
            Logger.log("Invalidating own box config.", level: .Message, context: .WidgetLayouting)
            let oldBoxConfig = boxConfig
            invalidateBoxConfig()
            let newBoxConfig = boxConfig
            // This prevents unnecessary calls to layout.
            // Only if this Widgets box config isn't changed, trigger a relayout.
            // For all children with changed box configs (also deeply nested ones)
            // layout will not have been called because of this comparison.
            // The first parent without a changed box config will trigger
            // a relayout for the whole subtree.
            // In case no Widget has no changed box config, the
            // relayout will be triggered in Root for the whole UI.
            // TODO: maybe there is a better solution
            if oldBoxConfig == newBoxConfig {
                Logger.log("Own box config is changed. Perform layout with previous constraints: \(String(describing: previousConstraints))".with(fg: .yellow), level: .Message, context: .WidgetLayouting)
                invalidateLayout()
            }
        }
    }

    public final func updateBoxConfig() {
        // TODO: implement inspection messages
        let currentBoxConfig = boxConfig
        let newBoxConfig = getBoxConfig()
        if currentBoxConfig != newBoxConfig {
            _boxConfig = newBoxConfig
            onBoxConfigChanged.invokeHandlers(BoxConfigChangedEvent(old: currentBoxConfig, new: newBoxConfig))
            invalidateLayout()
        }
        boxConfigInvalid = false
    }

    public func getBoxConfig() -> BoxConfig {
        var boxConfig = getContentBoxConfig()
        let paddingSize = padding.aggregateSize
        boxConfig += paddingSize
        let borderSize = borderWidth.aggregateSize
        boxConfig += borderSize
        return boxConfig
    }

    /**
    * Needs to be implemented by subclasses.
    * - Returns: the box config of the content of the Widget, which might be a drawing or other Widgets.
    */
    open func getContentBoxConfig() -> BoxConfig {
        fatalError("getContentBoxConfig() not implemented")
    }

    // TODO: maybe call this updateBoxConfig / or queueBoxConfigUpdate??? --> on next tick?
    @inlinable
    public final func invalidateBoxConfig() {
        if !mounted {
            #if DEBUG
            Logger.warn("Called invalidateBoxConfig() before Widget was mounted.")
            #endif
            return
        }
        if boxConfigInvalid {
            #if DEBUG
            Logger.warn("Called invalidateBoxConfig() on a Widget where box config is already invalid", context: .WidgetLayouting)
            #endif
            return
        }
        boxConfigInvalid = true
        lifecycleBus.publish(WidgetLifecycleMessage(sender: self, content: .BoxConfigInvalidated))
        #if DEBUG
        context.inspectionBus.publish(WidgetInspectionMessage(sender: self, content: .BoxConfigInvalidated))
        #endif
        onBoxConfigInvalidated.invokeHandlers(Void())
    }

    public final func layout(constraints: BoxConstraints) {
        let invocationId = getNextLifecycleMethodInvocationId(.layout)
        lifecycleMethodInvocationSignalBus.publish(.started(method: .layout, reason: .undefined, invocationId: invocationId, timestamp: context.applicationTime ))

        #if DEBUG
        Logger.log("Attempting layout".with(fg: .yellow), "on Widget: \(self).", level: .Message, context: .WidgetLayouting)
        #endif

        if !layoutInvalid, let previousConstraints = previousConstraints, constraints == previousConstraints {
            #if DEBUG
            Logger.log("Constraints equal pervious constraints and layout is not invalid.", "Not performing layout.".with(fg: .yellow), level: .Message, context: .WidgetLayouting)
            #endif
            return
        }
        
        if !layoutable {
            #if DEBUG
            Logger.warn("Called layout() on Widget that is not layoutable: \(self)", context: .WidgetLayouting)
            #endif
            return
        }

        if layouting {
            #if DEBUG
            Logger.warn("Called layout() on Widget while that Widget was still layouting: \(self)", context: .WidgetLayouting)
            #endif
            return
        }

        _layout(constraints: constraints)
    }

    @usableFromInline
    internal final func _layout(constraints: BoxConstraints) {
        if constraints.minWidth.isInfinite || constraints.minHeight.isInfinite {
            fatalError("Widget received constraints that contain infinite value in min size: \(self)")
        }

        layouting = true

        onLayoutingStarted.invokeHandlers(constraints)

        for child in children {
            child.position = .zero
        }

        let previousSize = size
        let isFirstRound = !layouted
        
        var preparedConstraints: BoxConstraints = constraints - padding.aggregateSize - borderWidth.aggregateSize
        if overflowX == .scroll {
            preparedConstraints.minSize.x = 0
            preparedConstraints.maxSize.x = .infinity
        }
        if overflowY == .scroll {
            preparedConstraints.minSize.y = 0
            preparedConstraints.maxSize.y = .infinity
        }

        let newUnconstrainedContentSize = performLayout(constraints: preparedConstraints)

        for child in children {
            child.position += DVec2(padding.left, padding.top)
        }
        
        let targetSize = newUnconstrainedContentSize + padding.aggregateSize + borderWidth.aggregateSize
        size = constraints.constrain(targetSize)
        
        // depending on whether scrolling gets enabled now, these two values may or may not be used
        maxScrollOffset = .zero
        minScrollOffset = DVec2(size - targetSize)

        var scrollingEnabled = (x: false, y: false)
        if overflowX == .scroll {
            scrollingEnabled.x = true
        }
        if overflowY == .scroll {
            scrollingEnabled.y = true
        }
        // TODO: implement logic for overflow == .auto
        self.scrollingEnabled = scrollingEnabled

        layouting = false
        layouted = true
        layoutInvalid = false
        
        // TODO: where to call this? after setting bounds or before?
        onLayoutingFinished.invokeHandlers(bounds.size)

        if previousSize != size && !isFirstRound {
            onSizeChanged.invokeHandlers(size)
            invalidateRenderState()
        }

        self.previousConstraints = constraints
    }

    open func performLayout(constraints: BoxConstraints) -> DSize2 {
        fatalError("performLayout(constraints:) not implemented.")
    }

    @inlinable
    public final func invalidateLayout() {
        if layoutInvalid {
            #if DEBUG
            Logger.warn("Called invalidateLayout() on a Widget where layout is already invalid: \(self)", context: .WidgetLayouting)
            #endif
            return
        }

        _invalidateLayout()
    }

    @usableFromInline
    internal final func _invalidateLayout() {
        #if (DEBUG)
        if countCalls {
            callCounter.count(.InvalidateLayout)
        }
        context.inspectionBus.publish(
            WidgetInspectionMessage(
                sender: self,
                content: .LayoutInvalidated))
        #endif
        layoutInvalid = true
        onLayoutInvalidated.invokeHandlers(Void())
        lifecycleBus.publish(WidgetLifecycleMessage(sender: self, content: .LayoutInvalidated))
    }

    /**
    Returns the rendered representation of the Widget. Updates the Widgets render state if it is invalid.
    */
    @inlinable
    public final func render(reason: RenderInvocationReason) -> RenderObject.IdentifiedSubTree {
        //print("invoked render on ", self)

        if renderState.invalid && mounted && !destroyed {
            #if DEBUG
            if countCalls {
                if callCounter.count(.Render) {
                    context.inspectionBus.publish(WidgetInspectionMessage(
                        sender: self, content: .RenderBurstThresholdExceeded))
                }
            }

            Logger.log("Render state of Widget: \(self) invalid. Rerendering.".with(fg: .yellow), level: .Message, context: .WidgetRendering)
            #endif

            updateRenderState(reason: .renderCalled(reason))
        } else if !mounted || destroyed {
            #if DEBUG
            Logger.log("Widget: \(self) is not mounted or already destroyed. Skip rendering.".with(fg: .yellow), level: .Message, context: .WidgetRendering)
            #endif
        } else {
            #if DEBUG
            Logger.log("Render state of Widget: \(self) valid. Using cached state.".with(fg: .yellow), level: .Message, context: .WidgetRendering)
            #endif
        }

        return renderState.content!
    }

    /**
    For internal use only. Use render() on the outside.
    Takes the output of renderContent() and wraps it in an identifiable container.
    Adds rendered output for debugging as well.
    */
    @usableFromInline
    internal final func updateRenderState(reason: UpdateRenderStateInvocationReason) {
        //print("::::::Update Render State", self, reason)

        if !renderState.invalid {
            #if DEBUG
            Logger.warn("Called updateRenderState on Widget where renderState is not invalid.".with(fg: .white, bg: .red), context: .WidgetRendering)
            #endif
            return
        } else if !mounted || destroyed {
            #if DEBUG
            Logger.warn("Called updateRenderState on Widget that is not yet mounted or was destroyed.".with(fg: .white, bg: .red), context: .WidgetRendering)
            #endif
            return
        }

        #if DEBUG
        let startTime = Date.timeIntervalSinceReferenceDate
        context.inspectionBus.publish(WidgetInspectionMessage(
            sender: self, content: .RenderingStarted))
        #endif

        let subTree = renderState.content ?? IdentifiedSubTreeRenderObject(id, [])
        let oldMainContent = renderState.mainContent
        renderState.content = subTree

        if visibility == .visible, mounted && layouted && !layouting {
            let newMainContent = renderContent()
            // if the content that was rendered by the inheriting Widget
            // is still the same object as the old one, invalidate is cache
            // to force a rerender
            // TODO: there might be a better approach to this
            if let newMainContent = newMainContent,
               let oldMainContent = oldMainContent, oldMainContent === newMainContent {
                    newMainContent.invalidateCache()
            }
            renderState.mainContent = newMainContent
            
            var newDebuggingContent = [RenderObject]()

            #if DEBUG
            if debugLayout {
                let layoutDebuggingRendering = renderLayoutDebuggingInformation()
                subTree.appendChild(layoutDebuggingRendering)
                newDebuggingContent.append(layoutDebuggingRendering)
            }

            if highlighted {
                let highlight = RenderStyleRenderObject(fillColor: .red) {
                    RectangleRenderObject(globalBounds)
                }
                subTree.appendChild(highlight)
                newDebuggingContent.append(highlight)
            }
            #endif

            /*let duration = Date.timeIntervalSinceReferenceDate - startTime
            if duration > 0.01 {
                print("updateRenderState took", duration, self)
            }*/

            renderState.debuggingContent = newDebuggingContent
            subTree.replaceChildren(([renderState.mainContent] + renderState.debuggingContent).compactMap { $0 })
        } else if visibility == .hidden {
            subTree.removeChildren()
            #if DEBUG
            Logger.warn("Called updateRenderState on Widget that cannot be rendered in it's current state.".with(fg: .white, bg: .red), context: .WidgetRendering)
            #endif
        }

        renderState.invalid = false

        #if DEBUG
        //print("::::RENDER STATE UPDATE TOOK", self, reason, Date.timeIntervalSinceReferenceDate - startTime)
        context.inspectionBus.publish(WidgetInspectionMessage(
            sender: self, content: .RenderingFinished))
        #endif
    }

    /**
    Should be used by inheriting Widgets to create their rendered representation.
    This function is called internally by the render() (which then calls updateRenderState()) function. So don't call this directly.
    It is allowed to access the current render state, modify the current RenderObject
    and return it again (this approach might increase performance for Widgets that often need
    to rerender as it avoids some class instatiations and mounting in the RenderObjectTree).
    */
    open func renderContent() -> RenderObject? {
        .Container { [unowned self] in
            children.map { $0.render(reason: .renderContentOfParent(self)) }
        }
    }

    private final func renderLayoutDebuggingInformation() -> RenderObject {
        RenderObject.Container {
            RenderObject.RenderStyle(strokeWidth: 1, strokeColor: FixedRenderValue(layoutDebuggingColor)) {
                RenderObject.Rectangle(globalBounds)
            }

            RenderObject.Text(
                "\(bounds.size.width) x \(bounds.size.height)",
                fontConfig: layoutDebuggingTextFontConfig,
                color: layoutDebuggingColor,
                topLeft: globalBounds.min)
        }
    }

    /**
    Pass a message up to the manging root node and request a render state update in the next cycle.
    */
    @inlinable
    public final func invalidateRenderState(deep: Bool = false) {
        if renderState.invalid {
            #if DEBUG
            Logger.warn("Called invalidateRenderState() when render state is already invalid on Widget: \(self)", context: .WidgetRendering)
            #endif
            return
        }

        if destroyed {
            #if DEBUG
            Logger.warn("Tried to call invalidateRenderState() on destroyed widget: \(self)", context: .WidgetRendering)
            #endif
            return
        }

        if !mounted {
            #if DEBUG
            Logger.warn("Called invalidateRenderState() on an unmounted Widget: \(self)", context: .WidgetRendering)
            #endif
            return
        }

        _invalidateRenderState(deep: deep)
    }

    @inlinable
    public final func invalidateRenderState(deep: Bool = false, after block: () -> ()) {
        block()
        invalidateRenderState(deep: deep)
    }

    @usableFromInline
    internal final func _invalidateRenderState(deep: Bool) {
        #if (DEBUG)
        if countCalls {
            callCounter.count(.InvalidateRenderState)
        }
        #endif
        if deep {
            for child in children {
                child.invalidateRenderState(deep: true)
            }
        }
        renderState.invalid = true
        onRenderStateInvalidated.invokeHandlers(self)
        lifecycleBus.publish(WidgetLifecycleMessage(sender: self, content: .RenderStateInvalidated))
        #if DEBUG
        context.inspectionBus.publish(WidgetInspectionMessage(sender: self, content: .RenderStateInvalidated))
        #endif
    }

    @discardableResult
    open func requestFocus() -> Self {
        if focusable {
            // TODO: maybe run requestfocus and let the context notify the focused widget of receiving focus?
            if mounted {
                //focusContext.requestFocus(self)
                context.requestFocus(self)
            } else {
                _ = onMounted.once { [unowned self] in
                    context.requestFocus(self)
                }
            }
        }
        return self
    }

    @inlinable
    public func dropFocus() {
        if focusable {
            _focused = false
        }
    }

    var nextTickHandlerRemovers: [() -> ()] = []

    /**
    Run something on the next tick.
    */
    public func nextTick(_ block: @escaping (Tick) -> ()) {
        let remove = context.onTick.once(block)
        nextTickHandlerRemovers.append(remove)
    }
    
    /**
    Can be used for debugging purposes to highlight a specific Widget, helping to identify it on the screen.
    Only available in debug builds.
    */
    @usableFromInline
    internal func flashHighlight() {
        #if DEBUG
        highlighted = true
        invalidateRenderState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self = self {
                self.nextTick() { _ in
                    self.highlighted = false
                    self.invalidateRenderState()
                }
            }
        }
        #else
        fatalError("flashHighlight() is only available in debug builds")
        #endif
    }

    // TODO: how to name this?
    public final func destroy() {
        for child in children {
            child.destroy()
        }
        
        mounted = false
        
        undoContextSetup()
        
        if var reference = reference {
            if reference.anyReferenced === self {
                reference.anyReferenced = nil
            }
        }

        // TODO: maybe automatically clear all EventHandlerManagers / WidgetEventHandlerManagers by using reflection?
        

        for remove in nextTickHandlerRemovers {
            remove()
        }

        parent = nil

        destroySelf()
        
        onDestroy.invokeHandlers(Void())

        onParentChanged.removeAllHandlers()
        //onAnyParentChanged.removeAllHandlers()
        onMounted.removeAllHandlers()
        onBoxConfigChanged.removeAllHandlers()
        onSizeChanged.removeAllHandlers()
        onLayoutInvalidated.removeAllHandlers()
        onLayoutingStarted.removeAllHandlers()
        onLayoutingFinished.removeAllHandlers()
        onRenderStateInvalidated.removeAllHandlers()
        onDestroy.removeAllHandlers()

        let mirror = Mirror(reflecting: self)
        for child in mirror.allChildren {
            if var manager = child.value as? AnyWidgetEventHandlerManager {
                manager.removeAllHandlers()
                manager.widget = nil
            } else if var manager = child.value as? AnyEventHandlerManager {
                manager.removeAllHandlers()
            }
        } 

        destroyed = true

        Logger.log("Destroyed Widget: \(self), \(id)", level: .Message, context: .Default)
    }

    open func destroySelf() {}

    deinit {
      if !destroyed {
        fatalError("Deinitialized Widget without calling destroy() first")
      }
      Logger.log("Deinitialized Widget: \(id) \(self)", level: .Message, context: .Default)
    }
}

extension Widget {
    public struct BoxConfigChangedEvent {
        public var old: BoxConfig
        public var new: BoxConfig
        public init(old: BoxConfig, new: BoxConfig) {
            self.old = old
            self.new = new
        }
    }

    public struct ReplacementContext {
        public var previousWidget: Widget?
        public var keyedWidgets: [String: Widget]
    }
}
