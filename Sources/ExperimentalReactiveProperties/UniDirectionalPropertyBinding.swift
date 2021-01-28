import Events

public class UniDirectionalPropertyBinding: PropertyBindingProtocol, EventfulObject {
  private var handlerRemovers = [() -> ()]()
  private var unregisterFunctions = [() -> ()]()

  public private(set) var destroyed: Bool = false
  public let onDestroyed = EventHandlerManager<Void>()

  private let source: AnyObject

  internal init<Source: ReactiveProperty, Sink: InternalValueSettableReactivePropertyProtocol>(source: Source, sink: Sink) where Source.Value == Sink.Value {    
    self.source = source

    var performingSinkUpdate = false

    handlerRemovers.append(source.onChanged { [unowned sink] in
      if performingSinkUpdate {
        return
      }
      performingSinkUpdate = true
      sink.value = $0.new
      performingSinkUpdate = false
    })
    handlerRemovers.append(source.onHasValueChanged { [unowned source, unowned sink] in
      if performingSinkUpdate {
        return
      }
      performingSinkUpdate = true
      sink.value = source.value
      performingSinkUpdate = false
    })
    handlerRemovers.append(source.onDestroyed { [unowned self] in
      destroy()
    })
    handlerRemovers.append(sink.onDestroyed { [unowned self] in
      destroy()
    })

    if source.hasValue {
      sink.value = source.value
    }
    
    unregisterFunctions.append(sink.registerBinding(self))
  }

  public func destroy() {
    if destroyed {
      return
    }
    for remove in handlerRemovers {
      remove()
    }
    for unregister in unregisterFunctions {
      unregister()
    }
    destroyed = true
    onDestroyed.invokeHandlers(())
    removeAllEventHandlers()
  }

  deinit {
    destroy()
  }
}