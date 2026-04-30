# frozen_string_literal: true

module TypedFormModel
  # Validates that nested form props (single or array) are themselves valid,
  # and propagates each child error to the parent at the parent attribute's path.
  #
  # Example:
  #   class OrderForm < TypedFormModel::Base
  #     prop :delivery_address, AddressForm
  #     prop :items, _Array(LineItemForm)
  #     validates_nested :delivery_address, :items
  #   end
  #
  #   form = OrderForm.from_params(params)
  #   form.valid?
  #   form.errors[:delivery_address] # => ["Street can't be blank", ...]
  #   form.errors[:items]            # => ["Quantity must be greater than 0", ...]
  #
  # Each child error becomes a separate parent error under the parent attribute
  # name, with the child's full_message preserved. Array nested props produce
  # one parent error per (item, child error) pair.
  class NestedValidator < ::ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      Array(value).each do |child|
        next if child.nil?
        next if child.respond_to?(:marked_for_destruction?) && child.marked_for_destruction?
        next if child.valid?
        child.errors.each do |child_error|
          record.errors.add(attribute, child_error.full_message)
        end
      end
    end
  end
end
