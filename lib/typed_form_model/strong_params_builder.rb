# frozen_string_literal: true

module TypedFormModel
  # Builds the strong-params whitelist for a form class. Scalar props become
  # their name as a string; array props become `{"name" => []}`; nested-form
  # props become `{"name_attributes" => SubForm.keys_for_permit}`.
  class StrongParamsBuilder
    def initialize(form_class)
      @form_class = form_class
    end

    def call
      form_class.literal_properties.map { |prop| entry_for(prop) }
    end

    private

    attr_reader :form_class

    def entry_for(prop)
      type = unwrap_nilable(prop.type)
      name = prop.name.to_s
      if array_of_form?(type)
        {"#{name}_attributes" => type.type.keys_for_permit}
      elsif form_class?(type)
        {"#{name}_attributes" => type.keys_for_permit}
      elsif array_type?(type)
        {name => []}
      else
        name
      end
    end

    def unwrap_nilable(type)
      type.is_a?(::Literal::Types::NilableType) ? type.type : type
    end

    def array_type?(type)
      type == Array || type.is_a?(::Literal::Types::ArrayType)
    end

    def form_class?(type)
      type.is_a?(::Class) && type <= ::TypedFormModel::Base
    end

    def array_of_form?(type)
      type.is_a?(::Literal::Types::ArrayType) && form_class?(type.type)
    end
  end
end
