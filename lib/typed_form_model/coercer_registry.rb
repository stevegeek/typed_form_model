# frozen_string_literal: true

module TypedFormModel
  # A registry of coercion procs keyed by declared prop type.
  #
  # Form classes each own a registry that inherits entries from their parent
  # (so subclasses automatically see built-in and parent-custom coercers).
  # Custom coercers are registered per-form via `register_coercer(type, &block)`
  # on the class body.
  #
  # Lookup order (used by `Base.default_coercer_for`):
  #   1. Exact registered entries (by class identity, via `lookup`)
  #   2. Built-in fallbacks for the primitive type families
  #      (Integer, Float, Numeric, BigDecimal, String, Symbol,
  #       Date/Time/DateTime, _Boolean, nested forms, arrays of forms)
  #   3. No coercer (the value is passed through to Literal unchanged)
  class CoercerRegistry
    def initialize(parent: nil)
      @entries = {}
      @parent = parent
    end

    # Register a coercion proc for a specific type. The proc receives the raw
    # input and must return the coerced value (or nil).
    def register(type, &block)
      raise ArgumentError, "register_coercer requires a block" unless block
      @entries[type] = block
      self
    end

    # Find a coercer for the given type. Returns nil if none registered and
    # no built-in fallback applies.
    def lookup(type)
      @entries[type] || @parent&.lookup(type)
    end

    # Returns a new registry that inherits from this one. Used when a
    # subclass declares its own custom coercers.
    def child
      self.class.new(parent: self)
    end
  end
end
