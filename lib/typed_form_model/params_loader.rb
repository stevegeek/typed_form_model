# frozen_string_literal: true

module TypedFormModel
  # Converts raw controller params (Hash or ActionController::Parameters) into
  # a kwargs Hash suitable for `FormClass.new(...)`. Filters to declared props,
  # symbolises keys. Routes Rails FormBuilder-style `*_attributes` keys back
  # to their underlying nested-form prop, converting indexed hashes for
  # array-of-form props into arrays.
  class ParamsLoader
    ATTRIBUTES_SUFFIX = "_attributes"

    def initialize(form_class)
      @form_class = form_class
    end

    def call(raw, persisted: false)
      return {persisted: persisted} if raw.nil?
      hash = to_hash(raw)
      attrs = hash.each_with_object({}) do |(key, value), acc|
        attach_entry(acc, key, value)
      end
      attrs[:persisted] = persisted
      attrs
    end

    private

    attr_reader :form_class

    def to_hash(raw)
      return raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      raw.to_h
    end

    def attach_entry(acc, key, value)
      key_str = key.to_s
      if key_str.end_with?(ATTRIBUTES_SUFFIX)
        base_key = key_str.delete_suffix(ATTRIBUTES_SUFFIX).to_sym
        return unless (prop = lookup_prop(base_key))
        acc[base_key] = coerce_attributes_key(prop, value)
      else
        sym = key.to_sym
        acc[sym] = value if lookup_prop(sym)
      end
    end

    def lookup_prop(name)
      form_class.literal_properties.find { |p| p.name == name }
    end

    # FormBuilder sends array-of-nested-form data as an indexed Hash
    # (`{"0" => {...}, "1" => {...}}`). Normalise back to an Array so the
    # prop's coercer (which expects an Array) handles each element.
    def coerce_attributes_key(prop, value)
      if array_of_form?(prop.type) && value.is_a?(::Hash)
        value.to_a.sort_by { |(idx, _)| idx.to_i }.map(&:last)
      else
        value
      end
    end

    def array_of_form?(type)
      inner = type.is_a?(::Literal::Types::NilableType) ? type.type : type
      inner.is_a?(::Literal::Types::ArrayType) &&
        inner.type.is_a?(::Class) && inner.type <= ::TypedFormModel::Base
    end
  end
end
