# frozen_string_literal: true

module TypedFormModel
  # Per-prop metadata captured at declaration time for options that Literal
  # doesn't know about (model-mapping, transforms). Immutable value object.
  # `model` and `attribute` are the parsed pieces of the DSL `from:` kwarg
  # (a Symbol fills only `attribute`; a "src.attr" String fills both).
  PropMetadata = Data.define(:model, :attribute, :transform) do
    # The target attribute name on the model; defaults to the prop name
    # when `from:` did not specify a rename.
    def model_attribute(prop_name) = attribute || prop_name

    # Is this prop mapped to the given source name (the first segment of a
    # dotted `from:`)?
    def maps_to?(model_name) = model == model_name
  end
end
