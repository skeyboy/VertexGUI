extension Experimental {
  public struct StylePropertySupportDefinitions: ExpressibleByArrayLiteral, Sequence {
    public var definitions: [StylePropertySupportDefinition]
    public var source: StylePropertySupportDefinition.Source = .unknown {
      didSet {
        for i in 0..<definitions.count {
          definitions[i].source = source
        }
      }
    }

    /** 
    A convenient api for defining supported properties.  
    
    Use it like:

        StylePropertySupportDefinition {
          ("someKey", type: .specific(SomeType.self))
          ("someOtherKey", type: .function({ $0 is SomeType }), value: { $0.property1 == 0 })
        }
     */
    public init(@DefinitionBuilder build: () -> [StylePropertySupportDefinition]) {
      self.init(build())
    }

    public init(_ definitions: [StylePropertySupportDefinition]) {
      self.definitions = definitions
    }

    public init(arrayLiteral elements: StylePropertySupportDefinition...) {
      self.init(elements)
    }

    public init(merge definitions: StylePropertySupportDefinitions...) throws {
      var byKey = [String: StylePropertySupportDefinition]()
      var merged = [StylePropertySupportDefinition]()

      for definition in definitions.flatMap { $0.definitions } {
        if byKey[definition.key.asString] != nil {
          throw MergingError.duplicateKey(
            key: definition.key.asString, 
            sources: [byKey[definition.key.asString]!.source, definition.source])
        }

        byKey[definition.key.asString] = definition
        merged.append(definition)
      }

      self.definitions = merged
    }

    public func makeIterator() -> some IteratorProtocol {
      definitions.makeIterator()
    }

    mutating public func declaredWith(source: StylePropertySupportDefinition.Source) -> Self {
      self.source = source
      return self
    }

    public func process(_ properties: [Experimental.StyleProperty]) -> (validProperties: [Experimental.StyleProperty], results: [String: ValidationResult]) {
      var validationResults = [String: ValidationResult]()
      var validProperties = [Experimental.StyleProperty]()

      for property in properties {
        
      }

      return (validProperties: properties, results: validationResults)
    }

    public enum MergingError: Error {
      case duplicateKey(key: String, sources: [StylePropertySupportDefinition.Source])
    }

    @_functionBuilder
    public struct DefinitionBuilder {
      public static func buildExpression(_ expression: (StyleKey,
        type: StylePropertyValueValidators.TypeValidator,
        value: StylePropertyValueValidators.ValueValidator)) -> StylePropertySupportDefinition {
          StylePropertySupportDefinition(key: expression.0,
            validators: StylePropertyValueValidators(
              typeValidator: expression.type,
              valueValidator: expression.value))
      }

      public static func buildExpression(_ expression: (StyleKey,
        type: StylePropertyValueValidators.TypeValidator)) -> StylePropertySupportDefinition {
          StylePropertySupportDefinition(key: expression.0,
            validators: StylePropertyValueValidators(
              typeValidator: expression.type))
      }

      public static func buildBlock(_ definitions: StylePropertySupportDefinition...) -> [StylePropertySupportDefinition] {
        definitions
      }
    }

    public enum ValidationResult {
      case unsupported, invalidType, invalidValue, duplicate
    }
  }
}