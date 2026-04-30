# frozen_string_literal: true

module TypedFormModel
  # Builds a form instance from one or more source objects (AR models,
  # OpenStructs, Hashes).
  #
  # Two entry points with intentionally different semantics:
  #
  #   from_model(record)   — single-source. The source segment of `from:` is
  #                          irrelevant (no ambiguity to dispatch on). Every
  #                          prop is read from `record` using its `from:`
  #                          rename or its own name.
  #   from_models(sources) — multi-source. A dotted `from:` is required per
  #                          prop to pick the source; props without a dotted
  #                          `from:` are skipped.
  #
  # In both cases the attribute segment of `from:` (or the Symbol form)
  # renames the source attribute, and a prop is skipped if the source
  # doesn't have the attribute at all (lets prop defaults fire). Edit-form
  # semantics: a source that has the attribute with a nil value still wins —
  # the form reflects the source.
  class ModelLoader
    def initialize(form_class)
      @form_class = form_class
    end

    # Single-source loader. Iterates every prop and reads it from `record`,
    # ignoring the source segment of `from:`. The attribute segment (or a
    # Symbol-form `from:`) is honoured for renames. `props:` (Array of
    # Symbols) restricts which props are pulled from the source; non-listed
    # props are skipped so their defaults fire.
    def from_model(record, persisted: true, context: {}, props: nil)
      allowed = build_allowed_set(props)
      attrs = {}
      form_class.literal_properties.each do |prop|
        next if allowed && !allowed.include?(prop.name)
        metadata = form_class.prop_metadata_for(prop.name)
        attr_name = (metadata&.model_attribute(prop.name) || prop.name).to_sym
        next unless attribute_present?(record, attr_name)

        attrs[prop.name] = read_attribute(record, attr_name)
      end
      form_class.new(persisted: persisted, context: context, **attrs)
    end

    # Multi-source loader. Each prop's `metadata.model` (parsed from the
    # source segment of a dotted `from:`) picks its source from `sources`.
    # Props with no source segment (or whose source isn't in `sources`) are
    # skipped — there's no implicit fallback when the caller is explicit
    # about having multiple sources.
    # `props:` (Array of Symbols) restricts which props are pulled across
    # sources; non-listed props are skipped so their defaults fire.
    def from_models(sources, persisted: true, context: {}, props: nil)
      allowed = build_allowed_set(props)
      attrs = {}
      form_class.literal_properties.each do |prop|
        next if allowed && !allowed.include?(prop.name)
        metadata = form_class.prop_metadata_for(prop.name)
        next unless metadata
        source = sources[metadata.model]
        next unless source

        attr_name = metadata.model_attribute(prop.name).to_sym
        next unless attribute_present?(source, attr_name)

        attrs[prop.name] = read_attribute(source, attr_name)
      end
      form_class.new(persisted: persisted, context: context, **attrs)
    end

    private

    attr_reader :form_class

    # Validate `props:` against the form's declared prop names so a typo
    # raises rather than silently producing an empty form. Returns a frozen
    # Set or nil (when no filter was given).
    def build_allowed_set(props)
      return nil if props.nil?
      requested = props.map(&:to_sym)
      declared = form_class.literal_properties.map(&:name).to_set
      unknown = requested.reject { |name| declared.include?(name) }
      unless unknown.empty?
        raise ArgumentError,
          "TypedFormModel: `props:` filter on `#{form_class.name}` references undeclared prop(s): #{unknown.inspect}. " \
          "Declared props: #{declared.to_a.inspect}."
      end
      requested.to_set
    end

    def attribute_present?(source, name)
      case source
      when ::Hash
        source.key?(name) || source.key?(name.to_s)
      else
        source.respond_to?(name)
      end
    end

    def read_attribute(source, name)
      case source
      when ::Hash
        source.key?(name) ? source[name] : source[name.to_s]
      else
        source.public_send(name)
      end
    end
  end
end
