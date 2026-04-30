# frozen_string_literal: true

module TypedFormModel
  # Given a form instance and a model name, extracts the attributes that map
  # to that model (via the source segment of each prop's dotted `from:`).
  # Applies the attribute-segment rename to produce AR-compatible attribute
  # keys. Skips nil values.
  class ModelAttributesExtractor
    def initialize(form)
      @form = form
      @form_class = form.class
    end

    # Always excluded from the result: :id (forms don't own IDs). Matches the
    # `attributes(include_id: false)` contract.
    IMPLICIT_EXCLUDES = [:id].freeze

    def call(model_name, except: [])
      excluded = IMPLICIT_EXCLUDES + Array.wrap(except).map(&:to_sym)
      attrs = form_class.literal_properties.each_with_object({}) do |prop, acc|
        metadata = form_class.prop_metadata_for(prop.name)
        next unless metadata&.maps_to?(model_name)

        model_key = metadata.model_attribute(prop.name).to_sym
        next if excluded.include?(model_key)

        value = form.send(prop.name)
        next if value.nil?

        acc[model_key] = value
      end
      ActiveSupport::HashWithIndifferentAccess.new(attrs)
    end

    private

    attr_reader :form, :form_class
  end
end
