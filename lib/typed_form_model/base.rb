# frozen_string_literal: true

module TypedFormModel
  # Clean-room base class for Rails form objects.
  class Base < ::Literal::Struct
    include ::Literal::Types
    extend ::ActiveModel::Naming
    include ::ActiveModel::Conversion
    include ::ActiveModel::Validations
    include ::ActiveModel::Validations::Callbacks

    UNSUPPORTED_OPTIONS = {
      optional: "Use `_Nilable(Type)` as the prop type instead (and omit `default:` to allow nil).",
      allow_nil: "Use `_Nilable(Type)` as the prop type for nilability; use ActiveModel validations for form-level presence.",
      allow_blank: "Use ActiveModel validations (`validates :field, presence: true`) instead of `allow_blank:`.",
      in: "Use ActiveModel validations (`validates :field, inclusion: { in: [...] }`) instead of `in:` on the prop."
    }.freeze

    # Sentinel for `copy` to bypass transforms. Frozen + private so external
    # callers can't pass `__skip_transforms: true` to skip transforms on
    # `Form.new(**permitted_params)` — only `copy` (which knows the sentinel)
    # may opt out.
    SKIP_TRANSFORMS = ::Object.new.freeze
    private_constant :SKIP_TRANSFORMS

    # Eagerly initialise per-class registries when a subclass is defined.
    # Lazy `||=` initialisation is unsafe if two threads concurrently look up
    # `coercer_registry` / `prop_metadata_registry` on a freshly-defined
    # subclass — each thread would build its own registry, one wins
    # assignment, registrations on the loser are silently lost.
    def self.inherited(subclass)
      super
      subclass.instance_variable_set(:@coercer_registry, coercer_registry.child)
      subclass.instance_variable_set(:@prop_metadata_registry, prop_metadata_registry.dup)
    end

    class << self
      # Per-class registry of custom coercers. Subclass registries inherit
      # from the parent; Base's starts empty (built-in coercers for Integer,
      # Float, Date etc. are resolved via `default_coercer_for`).
      def coercer_registry
        @coercer_registry ||= CoercerRegistry.new
      end

      # Register a custom type coercer on this form class.
      #   register_coercer(Money) { |v| v.is_a?(Money) ? v : Money.parse(v) }
      def register_coercer(type, &block)
        coercer_registry.register(type, &block)
      end

      # Override .new to capture persisted/context kwargs before they reach Literal
      # and to apply per-prop `transform:` procs against the context.
      # `__skip_transforms` only takes effect when the SKIP_TRANSFORMS sentinel
      # is passed (used internally by `copy`); any other value (including `true`)
      # is treated as a no-op so external callers can't bypass transforms.
      # `__provided_keys` carries an explicit Set of provided prop names from
      # `copy` (which knows the union of self + overrides). It's stripped from
      # kwargs before reaching Literal. External callers cannot use it: any
      # value is overwritten by `kwargs.keys.to_set` unless `copy` passes one.
      def new(**kwargs)
        skip_transforms = kwargs.delete(:__skip_transforms).equal?(SKIP_TRANSFORMS)
        explicit_provided = kwargs.delete(:__provided_keys)
        # Honour `__provided_keys` only when `copy` is also bypassing transforms.
        # External callers may set `__provided_keys` directly but it's ignored
        # unless the SKIP_TRANSFORMS sentinel was paired with it.
        explicit_provided = nil unless skip_transforms && explicit_provided.is_a?(::Set)
        persisted = kwargs.delete(:persisted) || false
        context = kwargs.delete(:context) || {}
        provided_keys = (explicit_provided || kwargs.keys.to_set).freeze
        kwargs = apply_transforms(kwargs, context) unless skip_transforms
        instance = super
        instance.instance_variable_set(:@persisted, persisted)
        instance.instance_variable_set(:@context, context)
        instance.instance_variable_set(:@provided_keys, provided_keys)
        instance
      end

      # Run each prop's `transform:` proc against its input value (before the
      # coercer fires inside super). Arity-1 procs get `(value)`; arity-2 get
      # `(value, context)`.
      def apply_transforms(kwargs, context)
        kwargs.each_with_object({}) do |(key, value), acc|
          metadata = prop_metadata_for(key)
          transform = metadata&.transform
          acc[key] = if transform
            (transform.arity == 1) ? transform.call(value) : transform.call(value, context)
          else
            value
          end
        end
      end

      # The name of the form, used by form builders. Falls back to param_key.
      def form_name
        model_name.param_key
      end

      # Cascade validation: parent invalid if any named nested-form prop (single or
      # array) is invalid. Propagates each child error to the parent under the
      # parent attribute path, using the child's full_message.
      def validates_nested(*attr_names)
        validates_with(::TypedFormModel::NestedValidator, attributes: attr_names)
      end

      # Build a form instance from raw controller params.
      # Accepts Hash, ActionController::Parameters, or nil.
      # `extract: true` unwraps the params from under the form's param_key
      # (`params[form_name]`) and permits them to `keys_for_permit` — the
      # common controller entry point.
      def from_params(raw, persisted: false, extract: false)
        raw = extract_form_params(raw) if extract
        new(**ParamsLoader.new(self).call(raw, persisted: persisted))
      end

      private

      def extract_form_params(raw)
        return {} unless raw.respond_to?(:fetch)
        nested = raw.fetch(form_name, nil) || raw.fetch(form_name.to_sym, nil)
        return {} unless nested
        nested = ::ActionController::Parameters.new(nested) unless nested.respond_to?(:permit)
        nested.permit(keys_for_permit)
      end

      public

      # Returns the strong-params whitelist for this form.
      def keys_for_permit
        StrongParamsBuilder.new(self).call
      end

      # Build a form instance from a single source record. Every prop is read
      # from `record` using its `from:` source-attribute (or its own name when
      # `from:` is omitted). The source segment of a dotted `from:` is ignored
      # in this single-source path. `props:` (Array of Symbols) restricts which
      # props are pulled.
      def from_model(record, persisted: true, context: {}, props: nil)
        ModelLoader.new(self).from_model(record, persisted: persisted, context: context, props: props)
      end

      # Build a form instance from multiple source records, keyed by the source
      # segment of each prop's dotted `from:` (e.g. `from: "user.role_id"` binds
      # to `sources[:user]`). Props without a dotted `from:` are skipped — there
      # is no implicit fallback when the caller provides multiple sources.
      #   Foo.from_models(user: user, profile: profile)
      #   Foo.from_models({user: user, profile: profile}, context: {...})
      # `props:` (Array of Symbols) restricts which props are pulled across
      # sources.
      def from_models(sources = nil, persisted: true, context: {}, props: nil, **kwargs)
        sources = kwargs if sources.nil? && kwargs.any?
        ModelLoader.new(self).from_models(sources || {}, persisted: persisted, context: context, props: props)
      end

      # Declare a prop. Props without a default are implicitly nilable with
      # default nil. Exception: array-shaped types (`Array`, `_Array(T)`,
      # `_Array(NestedForm)`) without a `default:` auto-default to `[]` and
      # are NOT made nilable — empty collections are the natural zero value.
      def prop(name, type, **options, &coercer)
        reject_unsupported_options!(name, options)

        metadata = capture_prop_metadata!(name, options)
        blank_to_nil_opt = options.delete(:blank_to_nil)
        apply_blank_to_nil = blank_to_nil_opt != false && blank_to_nil_applicable?(type)

        coercer ||= default_coercer_for(type)
        coercer = wrap_with_blank_to_nil(coercer) if apply_blank_to_nil

        # Predicates run on the user's declared type, not the auto-rewrapped
        # one. Without this, `prop :flag, _Nilable(_Boolean)` becomes
        # `_Nilable(_Nilable(_Boolean))` below and `boolean_type?` misses;
        # likewise `_Nilable(NestedForm)` would lose its `*_attributes=` setter.
        declared_type = type
        unless options.key?(:default)
          if array_shaped_type?(type)
            options[:default] = -> { [] }
          else
            type = _Nilable(type)
            options[:default] = -> {}
          end
        end
        super(name, type, **options, &coercer)

        define_method(:"#{name}?") { !!send(name) } if boolean_type?(declared_type) && !method_defined?(:"#{name}?")
        define_nested_attributes_setter(name) if nested_form_capable?(declared_type)

        store_prop_metadata(name, metadata)
      end

      # Reader for per-prop metadata. Walks ancestry so subclasses inherit.
      def prop_metadata_for(name)
        prop_metadata_registry[name]
      end

      def prop_metadata_registry
        @prop_metadata_registry ||= {}
      end

      def boolean_type?(type)
        type == _Boolean ||
          (type.is_a?(::Literal::Types::NilableType) && type.type == _Boolean)
      end

      private

      def reject_unsupported_options!(name, options)
        UNSUPPORTED_OPTIONS.each do |key, guidance|
          next unless options.key?(key)
          raise ArgumentError, "TypedFormModel: `#{key}:` is not supported on prop `#{name}`. #{guidance}"
        end
      end

      # Extracts TypedFormModel-specific options (from:, transform:) from the
      # options hash and returns a PropMetadata. Mutates options to remove them.
      # `from:` is parsed into [model, attribute]; the internal struct keeps
      # the two fields separately because ModelLoader / ModelAttributesExtractor
      # dispatch on them.
      def capture_prop_metadata!(name, options)
        model, attribute = parse_from_kwarg(name, options.delete(:from))
        PropMetadata.new(
          model: model,
          attribute: attribute,
          transform: options.delete(:transform) || nil
        )
      end

      # `from:` accepts:
      #   nil      → [nil, nil] (default, no mapping)
      #   Symbol   → [nil, sym] (single-source rename; not in multi-source dispatch)
      #   "src.attr" → [:src, :attr] (multi-source dispatch + attribute name)
      # Anything else, or a String not matching `<ident>.<ident>` (with each
      # segment a Ruby-style identifier), is rejected at class-definition time
      # to catch typos like " src.attr ", "1.2", or "src .attr".
      FROM_PATTERN = /\A[a-z_][a-zA-Z0-9_]*\.[a-z_][a-zA-Z0-9_]*\z/
      private_constant :FROM_PATTERN

      def parse_from_kwarg(prop_name, value)
        return [nil, nil] if value.nil?
        case value
        when Symbol
          [nil, value]
        when String
          unless FROM_PATTERN.match?(value)
            raise ArgumentError,
              "TypedFormModel: `from:` on prop `#{prop_name}` must be a Symbol or a 'source.attribute' " \
              "String of the form '<ident>.<ident>' (each segment a valid Ruby identifier, exactly one dot). Got: #{value.inspect}"
          end
          parts = value.split(".", 2)
          [parts[0].to_sym, parts[1].to_sym]
        else
          raise ArgumentError,
            "TypedFormModel: `from:` on prop `#{prop_name}` must be a Symbol or 'source.attribute' " \
            "String. Got: #{value.class}"
        end
      end

      def store_prop_metadata(name, metadata)
        prop_metadata_registry[name] = metadata
      end

      # Returns a coercer proc for the declared type. Custom registrations via
      # `register_coercer` take precedence over the built-ins below. Invalid
      # inputs (e.g. "abc" for Integer) produce nil rather than raising — forms
      # trust ActiveModel validations to reject bad data.
      def default_coercer_for(type)
        custom = coercer_registry.lookup(type)
        return custom if custom

        case type
        when Integer.singleton_class then coerce_integer
        when Float.singleton_class then coerce_float
        when BigDecimal.singleton_class then coerce_big_decimal
        when Numeric.singleton_class then coerce_numeric
        when String.singleton_class then coerce_string
        when Symbol.singleton_class then coerce_symbol
        when Date.singleton_class, Time.singleton_class, DateTime.singleton_class then coerce_temporal(type)
        else
          return coerce_boolean if type == _Boolean
          return coerce_nested_form(type) if form_class?(type)
          return coerce_array_of_nested_forms(type.type) if array_of_form?(type)
          nil
        end
      end

      def coerce_integer
        ->(v) do
          next nil if v.nil?
          next v if v.is_a?(::Integer)
          ::Kernel.Integer(v.to_s.tr("_", ""), 10, exception: false)
        end
      end

      def coerce_float
        ->(v) do
          next nil if v.nil?
          next v if v.is_a?(::Float)
          ::Kernel.Float(v.to_s, exception: false)
        end
      end

      def coerce_numeric
        int = coerce_integer
        flt = coerce_float
        ->(v) do
          next nil if v.nil?
          next v if v.is_a?(::Numeric)
          int.call(v) || flt.call(v)
        end
      end

      def coerce_big_decimal
        ->(v) do
          next nil if v.nil?
          next v if v.is_a?(::BigDecimal)
          ::Kernel.BigDecimal(v.to_s, exception: false)
        end
      end

      def coerce_string
        ->(v) { v.nil? ? nil : v.to_s }
      end

      def coerce_symbol
        ->(v) do
          next nil if v.nil?
          next v if v.is_a?(::Symbol)
          s = v.to_s
          next nil if s.bytesize > 64
          s.to_sym
        end
      end

      def coerce_temporal(type)
        to_method = if type == ::Date then :to_date
        elsif type == ::DateTime then :to_datetime
        elsif type == ::Time then :to_time
        end
        ->(v) do
          next nil if v.nil?
          # Exact-type passthrough (instance_of? not is_a?) — DateTime < Date,
          # so a Date-typed prop receiving a DateTime should still normalise
          # via `to_date` rather than leaking a DateTime to consumers.
          next v if v.instance_of?(type)
          # ActiveSupport::TimeWithZone is NOT a subclass of Time in modern
          # Rails; calling `to_time` on it returns a plain Time in the system
          # zone, silently dropping the explicit zone. For a Time-typed prop,
          # pass the TimeWithZone through unchanged so callers don't lose it.
          if type == ::Time && defined?(::ActiveSupport::TimeWithZone) && v.is_a?(::ActiveSupport::TimeWithZone)
            next v
          end
          # `String#to_date` etc. exist in Rails — guard against String here
          # so the 64-byte length cap applies on the parse branch below
          # rather than being bypassed by a Rails-supplied conversion.
          next v.public_send(to_method) if to_method && !v.is_a?(::String) && v.respond_to?(to_method)
          next nil unless v.is_a?(::String)
          # Date.parse has documented DoS profile on long adversarial input.
          next nil if v.bytesize > 64
          type.parse(v)
        rescue ::ArgumentError, ::TypeError, ::RangeError, ::Date::Error
          nil
        end
      end

      # Accepts an already-built form instance, a Hash of params, or any
      # source object (e.g. AR record) — coerced via `from_model` so that
      # `from_model(parent)` populates a nested form prop without per-form
      # boilerplate.
      def coerce_nested_form(form_type)
        ->(v) do
          next nil if v.nil?
          next v if v.is_a?(form_type)
          next form_type.from_params(v) if v.is_a?(::Hash)
          form_type.from_model(v)
        end
      end

      # Coerces each element in an array. Hash → from_params, existing form →
      # passthrough, anything else (AR record / value object) → from_model.
      def coerce_array_of_nested_forms(form_type)
        ->(v) do
          next nil if v.nil?
          Array(v).map do |el|
            case el
            when form_type then el
            when ::Hash then form_type.from_params(el)
            else form_type.from_model(el)
            end
          end
        end
      end

      def form_class?(type)
        type.is_a?(::Class) && type <= ::TypedFormModel::Base
      end

      def array_of_form?(type)
        type.is_a?(::Literal::Types::ArrayType) && form_class?(type.type)
      end

      # True for plain `Array`, `_Array(T)` of any element type. Used at
      # prop-declaration time to pick `[]` over `nil` as the implicit default.
      def array_shaped_type?(type)
        type == ::Array || type.is_a?(::Literal::Types::ArrayType)
      end

      # Rails FormBuilder treats any prop with a `#{name}_attributes=` setter
      # as a nested association. The setter itself is a no-op; actual coercion
      # happens in the prop's coercer block via `new`/`from_params`.
      def define_nested_attributes_setter(name)
        setter = :"#{name}_attributes="
        return if method_defined?(setter)
        define_method(setter) { |_attrs| }
      end

      def nested_form_capable?(type)
        inner = type.is_a?(::Literal::Types::NilableType) ? type.type : type
        form_class?(inner) || array_of_form?(inner)
      end

      def coerce_boolean
        ->(v) do
          next nil if v.nil?
          next v if v == true || v == false
          s = v.to_s.downcase
          next true if s == "true" || s == "1" || v == 1
          next false if s == "false" || s == "0" || v == 0 || s == ""
          nil
        end
      end

      # Arrays and booleans should never blank-to-nil: [].presence is nil (swallows empty
      # collections), and "" for a boolean needs explicit handling (tri-state vs default).
      def blank_to_nil_applicable?(type)
        return false if type == _Boolean
        return false if type == Array
        return false if type.is_a?(::Literal::Types::ArrayType)
        true
      end

      def wrap_with_blank_to_nil(inner_coercer)
        ->(v) do
          v = nil if v.respond_to?(:blank?) && v.blank? && !v.is_a?(::Array) && v != false
          inner_coercer ? inner_coercer.call(v) : v
        end
      end
    end

    attr_reader :context

    def persisted?
      @persisted
    end

    # Frozen Set of prop names that were explicitly provided when this form
    # was built (via `from_params`, `from_model(s)`, `new`, or `copy`).
    # Distinct from "non-nil" — a key set to `nil` is still provided. Used by
    # `merge` to layer PATCH semantics correctly.
    attr_reader :provided_keys

    # Indifferent access: form[:name] == form["name"]
    def [](key)
      send(key.to_sym)
    end

    # Returns a HashWithIndifferentAccess of non-nil attrs.
    # Excludes :id by default (forms don't own IDs).
    def attributes(include_id: false)
      result = self.class.literal_properties.each_with_object({}) do |prop, memo|
        value = send(prop.name)
        memo[prop.name] = value unless value.nil?
      end
      result.delete(:id) unless include_id
      ActiveSupport::HashWithIndifferentAccess.new(result)
    end

    # Returns a plain Hash (symbol keys) of all attrs incl. nils.
    def to_hash
      self.class.literal_properties.each_with_object({}) do |prop, memo|
        memo[prop.name] = send(prop.name)
      end
    end
    alias_method :to_h, :to_hash

    def to_params
      {self.class.form_name => attributes.to_h}
    end

    # Extract attributes whose `from:` source segment matches `model_name`.
    # Returns HashWithIndifferentAccess. Skips nil values. `except:` removes
    # keys AFTER the `from:` attribute-segment rename has been applied.
    def to_model_attributes(model_name, except: [])
      ModelAttributesExtractor.new(self).call(model_name, except: except)
    end

    def ==(other)
      other.class == self.class && other.to_hash == to_hash
    end
    alias_method :eql?, :==

    def hash
      [self.class, to_hash].hash
    end

    def as_json(options = {})
      to_hash.as_json(options)
    end

    def cache_key
      data = attributes
      return data.cache_key_with_version if data.respond_to?(:cache_key_with_version)
      return data.cache_key if data.respond_to?(:cache_key)
      return Digest::SHA1.hexdigest(data) if data.is_a?(::String)
      Digest::SHA1.hexdigest(Marshal.dump(data))
    end

    # Copy the form with attribute overrides. Validation errors are reset
    # on the copy — re-validate if you need error state preserved.
    # Transforms are NOT re-applied to the copied values (they already ran
    # when the original was built). Overrides are passed through as-is.
    # `provided_keys` on the copy = self.provided_keys ∪ overrides.keys.
    def copy(**overrides)
      merged_provided = (@provided_keys || ::Set.new) | overrides.keys.to_set
      self.class.new(
        __skip_transforms: self.class.const_get(:SKIP_TRANSFORMS),
        __provided_keys: merged_provided,
        persisted: @persisted,
        context: @context,
        **to_hash.merge(overrides)
      )
    end

    # Merge another form of the same class on top of this one. Keys that
    # `other` explicitly provided (via `provided_keys`) override `self`,
    # including explicit nils — so PATCH callers can un-set a field by
    # passing it as `nil`. Keys absent from `other.provided_keys` leave
    # `self`'s value untouched.
    def merge(other)
      unless other.is_a?(self.class)
        raise ArgumentError, "Cannot merge #{other.class} into #{self.class}"
      end
      overrides = other.to_hash.select { |k, _| other.provided_keys.include?(k) }
      copy(**overrides)
    end

    private_class_method :apply_transforms, :prop_metadata_registry, :coercer_registry
  end
end
