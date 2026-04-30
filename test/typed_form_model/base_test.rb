# frozen_string_literal: true

require "test_helper"

class TypedFormModel::BaseTest < ActiveSupport::TestCase
  # --- Declaration + instantiation ---

  def test_declares_a_prop_and_reads_it_back
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.new(name: "Alice")

    assert_equal "Alice", form.name
  end

  def test_prop_without_default_is_nilable
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.new

    assert_nil form.name
  end

  def test_prop_with_default_proc_fires_when_key_missing
    form_class = Class.new(TypedFormModel::Base) do
      prop :count, Integer, default: proc { 42 }
    end

    assert_equal 42, form_class.new.count
    assert_equal 7, form_class.new(count: 7).count
  end

  def test_rejects_optional_kwarg_with_helpful_error
    error = assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :name, String, optional: true
      end
    end
    assert_match(/optional:.*_Nilable/i, error.message)
  end

  def test_rejects_allow_nil_kwarg
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :name, String, allow_nil: true
      end
    end
  end

  def test_rejects_allow_blank_kwarg
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :name, String, allow_blank: true
      end
    end
  end

  def test_rejects_in_kwarg
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role, String, in: ["admin", "user"]
      end
    end
  end

  def test_rejects_from_kwarg_with_no_dot
    error = assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: "userrole_id"
      end
    end
    assert_match(/from:/, error.message)
    assert_match(/exactly one dot/, error.message)
  end

  def test_rejects_from_kwarg_with_multiple_dots
    error = assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: "a.b.c"
      end
    end
    assert_match(/exactly one dot/, error.message)
  end

  def test_rejects_from_kwarg_with_empty_segments
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: ".attr"
      end
    end
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: "model."
      end
    end
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: "."
      end
    end
  end

  def test_rejects_from_kwarg_with_non_symbol_non_string
    error = assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: 42
      end
    end
    assert_match(/Symbol or 'source.attribute' String/, error.message)
  end

  # --- Coercion ---

  def test_coerces_string_to_integer
    form_class = Class.new(TypedFormModel::Base) do
      prop :count, Integer
    end

    assert_equal 42, form_class.new(count: "42").count
  end

  def test_coerces_string_to_float
    form_class = Class.new(TypedFormModel::Base) do
      prop :amount, Float
    end

    assert_in_delta 3.14, form_class.new(amount: "3.14").amount
  end

  def test_coerces_string_to_boolean_true
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean, default: proc { false }
    end

    assert_equal true, form_class.new(active: "true").active
    assert_equal true, form_class.new(active: "1").active
    assert_equal true, form_class.new(active: 1).active
  end

  def test_coerces_string_to_boolean_without_default
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean
    end

    assert_equal true, form_class.new(active: "true").active
    assert_nil form_class.new.active
  end

  def test_coerces_string_to_boolean_false
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean, default: proc { false }
    end

    assert_equal false, form_class.new(active: "false").active
    assert_equal false, form_class.new(active: "0").active
    assert_equal false, form_class.new(active: 0).active
  end

  # Rails' check_box helper submits "" for unchecked boxes (via the paired
  # hidden input). Treat "" as false so forms that use check_box with a
  # non-nilable _Boolean prop round-trip correctly.
  def test_coerces_empty_string_to_boolean_false
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean, default: proc { false }
    end

    assert_equal false, form_class.new(active: "").active
  end

  def test_coerces_string_to_date
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    assert_equal Date.new(2026, 4, 17), form_class.new(on: "2026-04-17").on
  end

  def test_coerces_numeric_string_with_underscores
    form_class = Class.new(TypedFormModel::Base) do
      prop :amount, Numeric
    end

    assert_equal 1_000_000, form_class.new(amount: "1_000_000").amount
  end

  def test_coerces_numeric_string_with_leading_plus
    form_class = Class.new(TypedFormModel::Base) do
      prop :amount, Numeric
    end

    assert_equal 42, form_class.new(amount: "+42").amount
  end

  def test_invalid_date_string_returns_nil
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    assert_nil form_class.new(on: "not-a-date").on
  end

  def test_invalid_integer_string_returns_nil
    form_class = Class.new(TypedFormModel::Base) do
      prop :count, Integer
    end

    assert_nil form_class.new(count: "abc").count
  end

  # --- CoercerRegistry extensibility ---

  def test_custom_coercer_can_be_registered_on_form_class
    money_class = Struct.new(:amount_cents) do
      def self.parse(str) = new(Integer(str.delete(","), 10) * 100)
    end
    form_class = Class.new(TypedFormModel::Base) do
      register_coercer(money_class) do |v|
        if v.is_a?(money_class)
          v
        else
          (v.nil? ? nil : money_class.parse(v.to_s))
        end
      end
      prop :price, money_class
    end

    form = form_class.new(price: "1,234")

    assert_equal 123_400, form.price.amount_cents
  end

  # --- Blank-to-nil ---

  def test_blank_string_becomes_nil_by_default
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    assert_nil form_class.new(name: "").name
  end

  def test_blank_string_opt_out
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, blank_to_nil: false
    end

    assert_equal "", form_class.new(name: "").name
  end

  def test_blank_string_becomes_nil_for_integer
    form_class = Class.new(TypedFormModel::Base) do
      prop :count, Integer
    end

    assert_nil form_class.new(count: "").count
  end

  def test_empty_array_not_coerced_to_nil
    form_class = Class.new(TypedFormModel::Base) do
      prop :tags, _Array(String)
    end

    assert_equal [], form_class.new(tags: []).tags
  end

  # --- ActiveModel integration ---

  def test_valid_when_presence_validation_passes
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeForm"
      prop :name, String
      validates :name, presence: true
    end

    assert_predicate form_class.new(name: "Alice"), :valid?
  end

  def test_invalid_when_presence_validation_fails
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeForm"
      prop :name, String
      validates :name, presence: true
    end

    form = form_class.new
    refute_predicate form, :valid?
    assert_includes form.errors[:name], "can't be blank"
  end

  # --- Boolean predicate ---

  def test_boolean_prop_defines_predicate_method
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean, default: proc { false }
    end

    form = form_class.new(active: true)
    assert_respond_to form, :active?
    assert_equal true, form.active?
  end

  def test_boolean_predicate_returns_false_not_nil_when_value_unset
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean
    end

    form = form_class.new  # no value set → @active nil
    assert_equal false, form.active?
  end

  # --- validates_nested ---

  def test_validates_nested_propagates_child_errors_at_parent_attribute_path
    nested = Class.new(TypedFormModel::Base) do
      def self.name = "NestedPropagate"
      prop :x, String
      validates :x, presence: true
    end
    parent = Class.new(TypedFormModel::Base) do
      def self.name = "ParentPropagate"
      validates_nested :nested
    end
    parent.prop :nested, nested

    form = parent.new(nested: nested.new)

    refute_predicate form, :valid?
    assert form.errors[:nested].any?,
      "expected parent.errors[:nested] to receive propagated child errors"
    assert form.errors[:nested].any? { |m| m.include?("can't be blank") },
      "expected child full_message to be propagated; got #{form.errors[:nested].inspect}"
  end

  def test_validates_nested_propagates_errors_from_each_invalid_item_in_array
    item = Class.new(TypedFormModel::Base) do
      def self.name = "ItemNested"
      prop :sku, String
      validates :sku, presence: true
    end
    parent = Class.new(TypedFormModel::Base) do
      def self.name = "ParentArrayNested"
      include ::Literal::Types

      validates_nested :items
    end
    parent.prop :items, ::Literal::Types::ArrayType.new(item)

    form = parent.new(items: [item.new, item.new])

    refute_predicate form, :valid?
    assert_operator form.errors[:items].size, :>=, 2,
      "expected one parent error per (item, child error) pair; got #{form.errors[:items].inspect}"
  end

  def test_validates_nested_skips_nil_child
    nested = Class.new(TypedFormModel::Base) do
      def self.name = "NestedNilSkip"
      prop :x, String
      validates :x, presence: true
    end
    parent = Class.new(TypedFormModel::Base) do
      def self.name = "ParentNilSkip"
      validates_nested :nested
    end
    parent.prop :nested, nested

    form = parent.new(nested: nil)

    form.valid?
    assert_empty form.errors[:nested],
      "nil child must not contribute child errors; presence is a separate validation"
  end

  def test_validates_nested_honours_valid_children
    nested = Class.new(TypedFormModel::Base) do
      def self.name = "NestedValid"
      prop :x, String
      validates :x, presence: true
    end
    parent = Class.new(TypedFormModel::Base) do
      def self.name = "ParentValid"
      validates_nested :nested
    end
    parent.prop :nested, nested

    form = parent.new(nested: nested.new(x: "ok"))

    assert_predicate form, :valid?
    assert_empty form.errors[:nested]
  end

  def test_validates_nested_skips_marked_for_destruction_children
    nested = Class.new(TypedFormModel::Base) do
      def self.name = "NestedMarkedDestroy"
      prop :x, String
      validates :x, presence: true
      def marked_for_destruction?
        true
      end
    end
    parent = Class.new(TypedFormModel::Base) do
      def self.name = "ParentMarkedDestroy"
      validates_nested :nested
    end
    parent.prop :nested, nested

    form = parent.new(nested: nested.new)  # invalid in isolation

    assert_predicate form, :valid?,
      "children with marked_for_destruction? == true must be skipped"
    assert_empty form.errors[:nested]
  end

  # --- Instance API ---

  def test_attributes_excludes_nil_values
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    form = form_class.new(name: "Alice")
    attrs = form.attributes

    assert_equal "Alice", attrs[:name]
    refute attrs.key?(:age)
  end

  def test_attributes_is_indifferent_access
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.new(name: "Alice")

    assert_equal "Alice", form.attributes[:name]
    assert_equal "Alice", form.attributes["name"]
  end

  def test_indexer_is_indifferent
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.new(name: "Alice")

    assert_equal "Alice", form[:name]
    assert_equal "Alice", form["name"]
  end

  def test_to_hash_includes_all_attrs_with_symbol_keys
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    form = form_class.new(name: "Alice")

    assert_equal({name: "Alice", age: nil}, form.to_hash)
  end

  def test_persisted_defaults_to_false
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    refute_predicate form_class.new(name: "x"), :persisted?
  end

  def test_persisted_can_be_set
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    assert_predicate form_class.new(name: "x", persisted: true), :persisted?
  end

  def test_context_defaults_to_empty_hash
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    assert_equal({}, form_class.new(name: "x").context)
  end

  def test_context_can_be_set
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.new(name: "x", context: {lang: "en"})

    assert_equal({lang: "en"}, form.context)
  end

  def test_equality_on_attributes_and_class
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    a = form_class.new(name: "Alice")
    b = form_class.new(name: "Alice")
    c = form_class.new(name: "Bob")

    assert_equal a, b
    refute_equal a, c
  end

  def test_copy_does_not_reapply_transforms
    # Non-idempotent transform: prefixing "Mx " each time would produce "Mx Mx Alice"
    # on copy if transforms re-ran.
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, transform: ->(v) { "Mx #{v}" }
    end

    original = form_class.new(name: "Alice")
    assert_equal "Mx Alice", original.name

    copy = original.copy
    assert_equal "Mx Alice", copy.name, "copy should not re-prefix the already-transformed value"
  end

  def test_copy_allows_clearing_a_field_with_nil
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    original = form_class.new(name: "Alice", age: 30)
    copy = original.copy(name: nil)

    assert_nil copy.name
    assert_equal 30, copy.age
  end

  def test_copy_produces_new_form_with_overrides
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    original = form_class.new(name: "Alice", age: 30)
    copy = original.copy(age: 31)

    assert_equal "Alice", copy.name
    assert_equal 31, copy.age
    assert_equal 30, original.age, "original should not mutate"
  end

  # --- from_params ---

  def test_from_params_with_symbol_keys
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    form = form_class.from_params({name: "Alice", age: "30"})

    assert_equal "Alice", form.name
    assert_equal 30, form.age
  end

  def test_from_params_with_string_keys
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    form = form_class.from_params({"name" => "Alice", "age" => "30"})

    assert_equal "Alice", form.name
    assert_equal 30, form.age
  end

  def test_from_params_ignores_unknown_keys
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.from_params({name: "Alice", unknown: "ignored", extra: 42})

    assert_equal "Alice", form.name
  end

  def test_from_params_returns_empty_form_when_given_nil
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.from_params(nil)

    assert_nil form.name
  end

  def test_from_params_persisted_flag
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.from_params({name: "Alice"}, persisted: true)

    assert_predicate form, :persisted?
  end

  def test_from_params_with_extract_unwraps_from_form_key
    # Rails controller params look like {<form_name> => {<attr> => value}}.
    # `extract: true` unwraps under the form's param_key and auto-permits.
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "TwoFactorSetup"
      prop :otp, String
      prop :password, String
    end
    key = form_class.form_name

    raw = ActionController::Parameters.new(
      key => {"otp" => "123456", "password" => "secret"}
    )
    form = form_class.from_params(raw, extract: true)

    assert_equal "123456", form.otp
    assert_equal "secret", form.password
  end

  def test_from_params_with_extract_returns_empty_form_when_key_absent
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "TwoFactorSetup2"
      prop :otp, String
    end

    raw = ActionController::Parameters.new({})
    form = form_class.from_params(raw, extract: true)

    assert_nil form.otp
  end

  def test_from_params_accepts_action_controller_parameters
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    params = ActionController::Parameters.new(name: "Alice", age: "30").permit(:name, :age)
    form = form_class.from_params(params)

    assert_equal "Alice", form.name
    assert_equal 30, form.age
  end

  # --- keys_for_permit ---

  def test_keys_for_permit_returns_scalar_prop_names
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    assert_equal ["name", "age"], form_class.keys_for_permit
  end

  def test_keys_for_permit_returns_array_wrapped_for_array_props
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :tags, _Array(String)
    end

    assert_includes form_class.keys_for_permit, "name"
    assert_includes form_class.keys_for_permit, {"tags" => []}
  end

  # --- Model mapping (from: / to_model_attributes) ---

  def test_from_kwarg_binds_prop_to_a_model_name
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
      prop :category_id, Integer, from: "user.category_id"
      prop :title, String, from: "profile.title"
    end

    form = form_class.new(name: "Alice", category_id: 5, title: "CEO")

    assert_equal({name: "Alice", category_id: 5}, form.to_model_attributes(:user).to_h.symbolize_keys)
    assert_equal({title: "CEO"}, form.to_model_attributes(:profile).to_h.symbolize_keys)
  end

  def test_to_model_attributes_returns_indifferent_hash
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
    end

    attrs = form_class.new(name: "Alice").to_model_attributes(:user)

    assert_equal "Alice", attrs[:name]
    assert_equal "Alice", attrs["name"]
  end

  def test_dotted_from_kwarg_renames_attribute_on_model
    form_class = Class.new(TypedFormModel::Base) do
      prop :user_name, String, from: "user.name"
    end

    form = form_class.new(user_name: "Alice")

    assert_equal({name: "Alice"}, form.to_model_attributes(:user).to_h.symbolize_keys)
  end

  def test_to_model_attributes_skips_nil_values_by_default
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
      prop :age, Integer, from: "user.age"
    end

    form = form_class.new(name: "Alice")

    assert_equal({name: "Alice"}, form.to_model_attributes(:user).to_h.symbolize_keys)
  end

  def test_to_model_attributes_excludes_id_by_default
    form_class = Class.new(TypedFormModel::Base) do
      prop :id, Integer, from: "user.id"
      prop :name, String, from: "user.name"
    end

    attrs = form_class.new(id: 5, name: "Alice").to_model_attributes(:user)

    assert_equal({name: "Alice"}, attrs.to_h.symbolize_keys)
  end

  def test_to_model_attributes_except_excludes_keys
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
      prop :password, String, from: "user.password"
    end

    form = form_class.new(name: "Alice", password: "secret")

    assert_equal({name: "Alice"}, form.to_model_attributes(:user, except: [:password]).to_h.symbolize_keys)
  end

  def test_props_without_dotted_from_are_not_in_any_model_map
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
      prop :free_text, String
    end

    form = form_class.new(name: "Alice", free_text: "hello")

    assert_equal({name: "Alice"}, form.to_model_attributes(:user).to_h.symbolize_keys)
  end

  # --- from_model / from_models ---

  def test_from_model_reads_attrs_via_dotted_from
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "model.name"
      prop :age, Integer, from: "model.age"
    end
    model = Data.define(:name, :age).new(name: "Alice", age: 30)

    form = form_class.from_model(model)

    assert_equal "Alice", form.name
    assert_equal 30, form.age
    assert_predicate form, :persisted?
  end

  def test_from_model_uses_dotted_from_for_renamed_attrs
    form_class = Class.new(TypedFormModel::Base) do
      prop :user_name, String, from: "model.name"
    end
    model = Data.define(:name).new(name: "Alice")

    form = form_class.from_model(model)

    assert_equal "Alice", form.user_name
  end

  def test_from_kwarg_symbol_renames_source_attribute_on_single_source_from_model
    # Symbol form: from: :other_name renames the source attribute on a
    # single-source from_model. The first segment is absent (no source key)
    # so this prop is NOT in any multi-source from_models mapping.
    form_class = Class.new(TypedFormModel::Base) do
      prop :surname, String, from: :last_name
    end
    record = Data.define(:last_name).new(last_name: "Archer")

    form = form_class.from_model(record)

    assert_equal "Archer", form.surname
  end

  def test_from_models_with_multiple_sources
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
      prop :title, String, from: "profile.title"
    end
    user = Data.define(:name).new(name: "Alice")
    profile = Data.define(:title).new(title: "CEO")

    form = form_class.from_models(user: user, profile: profile)

    assert_equal "Alice", form.name
    assert_equal "CEO", form.title
  end

  def test_from_models_with_dotted_from_parses_path
    form_class = Class.new(TypedFormModel::Base) do
      prop :user_job_title, String, from: "user_profile.position_name"
      prop :role_id, Integer, from: "user.role_id"
    end
    user_profile = Data.define(:position_name).new(position_name: "CEO")
    user = Data.define(:role_id).new(role_id: 7)

    form = form_class.from_models(user_profile: user_profile, user: user)

    assert_equal "CEO", form.user_job_title
    assert_equal 7, form.role_id
    assert_equal({position_name: "CEO"}, form.to_model_attributes(:user_profile).to_h.symbolize_keys)
    assert_equal({role_id: 7}, form.to_model_attributes(:user).to_h.symbolize_keys)
  end

  def test_from_models_with_hash_source_preserves_falsy_values
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean, from: "model.active"
    end

    form = form_class.from_models(model: {active: false})

    assert_equal false, form.active
  end

  def test_from_model_accepts_context
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "model.name", transform: ->(v, ctx) { "#{ctx[:prefix]}#{v}" }
    end
    model = Data.define(:name).new(name: "Alice")

    form = form_class.from_model(model, context: {prefix: "Mx "})

    assert_equal "Mx Alice", form.name
    assert_equal({prefix: "Mx "}, form.context)
  end

  def test_from_models_accepts_context
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
    end
    user = Data.define(:name).new(name: "Alice")

    form = form_class.from_models({user: user}, context: {lang: "en"})

    assert_equal({lang: "en"}, form.context)
  end

  def test_from_model_preserves_nil_from_source_when_prop_is_nilable
    form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types

      prop :tagline, _Nilable(String), from: "model.tagline", default: proc { "Not set" }
    end
    model = Data.define(:tagline).new(tagline: nil)

    form = form_class.from_model(model)

    # Edit-form semantics: if the source responds to the attribute (even
    # with nil), the form reflects the source — don't fall back to default.
    assert_nil form.tagline
  end

  def test_from_model_uses_default_when_source_does_not_respond
    form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types

      prop :tagline, _Nilable(String), from: "model.tagline", default: proc { "Not set" }
    end
    model = Data.define.new  # no tagline attr at all

    form = form_class.from_model(model)

    assert_equal "Not set", form.tagline
  end

  def test_from_models_with_hash_source_preserves_nil_keyed_values
    form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types

      prop :tagline, _Nilable(String), from: "model.tagline", default: proc { "Not set" }
    end

    # Hash has the key (with nil value) — legacy treated this as "source wins".
    form = form_class.from_models(model: {tagline: nil})

    assert_nil form.tagline
  end

  def test_from_model_loads_props_without_model
    # `from_model` is single-source — every prop is read from the record
    # regardless of `model:`. The `model:` declaration only matters for the
    # multi-source `from_models` entry point (see test below).
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :free_text, String
    end
    model = Data.define(:name, :free_text).new(name: "Alice", free_text: "loaded-from-model")

    form = form_class.from_model(model)

    assert_equal "Alice", form.name
    assert_equal "loaded-from-model", form.free_text
  end

  def test_from_model_ignores_source_segment_when_record_has_the_attribute
    # The source segment of `from:` is for `from_models` dispatch only.
    # `from_model` is single-source, so a prop declared `from: "user.name"`
    # still loads from the record when the record has the attribute —
    # there's no other source to dispatch to.
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
    end
    record = Data.define(:name).new(name: "Alice")

    form = form_class.from_model(record)

    assert_equal "Alice", form.name
  end

  def test_from_model_skips_props_when_record_lacks_the_attribute
    # Virtual props / form-only fields not present on the record don't get
    # populated, so the prop's default fires instead.
    form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types

      prop :name, String
      prop :virtual, _Nilable(String), default: proc { "default" }
    end
    record = Data.define(:name).new(name: "Alice")  # no `virtual`

    form = form_class.from_model(record)

    assert_equal "Alice", form.name
    assert_equal "default", form.virtual
  end

  def test_from_models_skips_props_without_dotted_from
    # Counterpoint to from_model: in multi-source mode, the source segment of
    # `from:` is the dispatch mechanism. A prop without a dotted `from:` has
    # no source to point at and is skipped.
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name"
      prop :free_text, String  # no from: → not dispatched in from_models
    end
    user = Data.define(:name, :free_text).new(name: "Alice", free_text: "ignored")

    form = form_class.from_models(user: user)

    assert_equal "Alice", form.name
    assert_nil form.free_text
  end

  # --- Nested-form auto-coercion (from_model on prop's form_type) ---

  def test_from_model_auto_coerces_nested_form_prop_from_record
    # A single nested-form prop (`property :foo, SomeForm`) gets the bare
    # record from the parent's `from_model`. The auto-coercer should detect
    # the AR-like value and route it through `SomeForm.from_model`.
    address_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "AddressForm"
      prop :city, String
    end
    user_form_class = Class.new(TypedFormModel::Base) do
      define_singleton_method(:address_form_class) { address_form_class }
    end
    user_form_class.prop :address, address_form_class

    user_record = Data.define(:address).new(address: Data.define(:city).new(city: "Berlin"))

    form = user_form_class.from_model(user_record)

    assert_kind_of address_form_class, form.address
    assert_equal "Berlin", form.address.city
  end

  def test_from_model_auto_coerces_array_of_nested_forms_from_collection
    # `_Array(SomeForm)` populated from `record.things` (a collection of
    # AR-like objects) coerces each element via `SomeForm.from_model`.
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemForm"
      include ::Literal::Types

      prop :sku, String
      prop :quantity, Integer
    end
    cart_form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types
    end
    cart_form_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    item_data = Data.define(:sku, :quantity)
    cart_record = Data.define(:items).new(items: [
      item_data.new(sku: "ABC", quantity: 2),
      item_data.new(sku: "XYZ", quantity: 5)
    ])

    form = cart_form_class.from_model(cart_record)

    assert_equal 2, form.items.size
    form.items.each { |i| assert_kind_of item_form_class, i }
    assert_equal "ABC", form.items[0].sku
    assert_equal 2, form.items[0].quantity
    assert_equal "XYZ", form.items[1].sku
    assert_equal 5, form.items[1].quantity
  end

  def test_array_of_nested_forms_coercer_passes_through_existing_form_instances
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemForm"
      prop :sku, String
    end
    cart_form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types
    end
    cart_form_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    existing = item_form_class.new(sku: "PRE-BUILT")

    form = cart_form_class.new(items: [existing])

    assert_same existing, form.items.first
  end

  def test_array_of_nested_forms_coercer_accepts_hashes_via_from_params
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemForm"
      include ::Literal::Types

      prop :sku, String
      prop :quantity, Integer
    end
    cart_form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types
    end
    cart_form_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    form = cart_form_class.new(items: [
      {sku: "A", quantity: "3"},                   # symbol keys, string-int
      {"sku" => "B", "quantity" => 4}              # string keys
    ])

    assert_equal 2, form.items.size
    form.items.each { |i| assert_kind_of item_form_class, i }
    assert_equal "A", form.items[0].sku
    assert_equal 3, form.items[0].quantity
    assert_equal "B", form.items[1].sku
    assert_equal 4, form.items[1].quantity
  end

  # --- Nested form props ---

  def test_nested_form_prop_accepts_instance
    address_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "AddressForm"
      prop :city, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "ContainerForm"
      define_singleton_method(:address_form_class) { address_form_class }
    end
    container_class.prop :address, address_form_class

    address = address_form_class.new(city: "Berlin")
    form = container_class.new(address: address)

    assert_equal "Berlin", form.address.city
  end

  def test_nested_form_prop_coerces_hash_to_instance
    address_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "AddressForm2"
      prop :city, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "ContainerForm2"
    end
    container_class.prop :address, address_form_class

    form = container_class.from_params({address: {city: "Paris"}})

    assert_instance_of address_form_class, form.address
    assert_equal "Paris", form.address.city
  end

  # Rails FormBuilder sends nested data under the `*_attributes` suffix, not
  # the bare prop name. ParamsLoader must route these back to the underlying
  # prop so nested forms round-trip through controllers correctly.
  def test_nested_form_accepts_attributes_suffixed_key
    address_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "AddressFormBuilderTest"
      prop :city, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "ContainerFormBuilderTest"
    end
    container_class.prop :address, address_form_class

    form = container_class.from_params({address_attributes: {city: "Madrid"}})

    assert_instance_of address_form_class, form.address
    assert_equal "Madrid", form.address.city
  end

  def test_array_of_nested_forms_accepts_attributes_suffixed_key
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemFormBuilderTest"
      prop :sku, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "BasketFormBuilderTest"
    end
    container_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    # Rails sends indexed hashes for array-of-form nested attributes
    form = container_class.from_params({
      items_attributes: {"0" => {sku: "ABC"}, "1" => {sku: "DEF"}}
    })

    assert_equal 2, form.items.size
    assert_equal ["ABC", "DEF"], form.items.map(&:sku)
  end

  def test_nested_form_defines_attributes_setter_for_form_builder
    address_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "AddressForm3"
      prop :city, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "ContainerForm3"
    end
    container_class.prop :address, address_form_class

    # FormBuilder's nested_attributes_association? probe calls respond_to?(:X_attributes=)
    assert container_class.new.respond_to?(:address_attributes=)
  end

  def test_keys_for_permit_expands_nested_form_to_attributes_key
    address_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "AddressForm4"
      prop :city, String
      prop :zipcode, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "ContainerForm4"
    end
    container_class.prop :address, address_form_class

    permit_keys = container_class.keys_for_permit
    nested_entry = permit_keys.find { |k| k.is_a?(Hash) && k.key?("address_attributes") }
    assert nested_entry, "expected keys_for_permit to include {\"address_attributes\" => [...]}"
    assert_includes nested_entry["address_attributes"], "city"
    assert_includes nested_entry["address_attributes"], "zipcode"
  end

  # --- Array of nested forms ---

  def test_array_of_nested_forms_accepts_instances
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemForm"
      prop :sku, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "BasketForm"
    end
    container_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    item = item_form_class.new(sku: "ABC")
    form = container_class.new(items: [item])

    assert_equal "ABC", form.items.first.sku
  end

  def test_array_of_nested_forms_coerces_each_hash
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemForm2"
      prop :sku, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "BasketForm2"
    end
    container_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    form = container_class.from_params({items: [{sku: "ABC"}, {sku: "DEF"}]})

    assert_equal 2, form.items.size
    assert_equal ["ABC", "DEF"], form.items.map(&:sku)
  end

  # --- transform: option ---

  def test_transform_proc_runs_before_coercion
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, transform: ->(v) { v&.upcase }
    end

    assert_equal "ALICE", form_class.new(name: "alice").name
  end

  def test_transform_arity_2_receives_context
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, transform: ->(v, ctx) { "#{ctx[:prefix]}#{v}" }
    end

    form = form_class.new(name: "Alice", context: {prefix: "Mx "})

    assert_equal "Mx Alice", form.name
  end

  # --- End-to-end round trip ---

  def test_params_into_form_into_model_attrs
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "E2EForm"
      prop :name, String, from: "user.name"
      prop :age, Integer, from: "user.age"
      prop :title, String, from: "profile.role_title"
      validates :name, presence: true
    end

    form = form_class.from_params({name: "Alice", age: "30", title: "Founder"})

    assert_predicate form, :valid?
    assert_equal "Alice", form.name
    assert_equal 30, form.age
    user_attrs = form.to_model_attributes(:user).to_h.symbolize_keys
    profile_attrs = form.to_model_attributes(:profile).to_h.symbolize_keys

    assert_equal({name: "Alice", age: 30}, user_attrs)
    assert_equal({role_title: "Founder"}, profile_attrs)
  end

  # --- Security & correctness regressions ---

  # Fix 1: Unrecognised boolean strings ("yes", "on", arbitrary input) must
  # coerce to nil — same contract as Integer/Float/Date — so validations get
  # an honest "no value" rather than a passthrough that silently bypasses
  # type checks.
  def test_coerce_boolean_returns_nil_for_unrecognised_string
    form_class = Class.new(TypedFormModel::Base) do
      prop :active, _Boolean
    end

    assert_nil form_class.new(active: "yes").active
    assert_nil form_class.new(active: "on").active
    assert_nil form_class.new(active: "garbage").active
  end

  # Fix 2: Date.parse has a documented DoS profile against long adversarial
  # input. Cap at 64 bytes — well above any realistic ISO date/time string.
  def test_coerce_temporal_returns_nil_for_oversized_string
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    oversized = "2026-04-17" + ("x" * 60) # 70 bytes, > 64
    assert_nil form_class.new(on: oversized).on
  end

  # Fix 3: Unbounded `to_sym` on user input is a memory-pinning DoS in older
  # Rubies. Cap at 64 bytes; happy path still works.
  def test_coerce_symbol_returns_nil_for_oversized_string
    form_class = Class.new(TypedFormModel::Base) do
      prop :tag, Symbol
    end

    assert_nil form_class.new(tag: "x" * 65).tag
  end

  def test_coerce_symbol_passes_a_normal_symbol_through
    form_class = Class.new(TypedFormModel::Base) do
      prop :tag, Symbol
    end

    assert_equal :morning, form_class.new(tag: :morning).tag
    assert_equal :afternoon, form_class.new(tag: "afternoon").tag
  end

  # Fix 4: Subclass registries must be isolated. Lazy `||=` on a fresh
  # subclass races under concurrent access (two threads can each build a
  # registry; one wins assignment, registrations on the loser are lost).
  # Eager init via `inherited` removes the race; here we lock the isolation
  # invariant: each subclass sees only its own coercers + parent's, not its
  # siblings'.
  def test_subclass_registries_are_isolated_from_sibling_subclasses
    type_a = Class.new
    type_b = Class.new

    sub_a = Class.new(TypedFormModel::Base) do
      register_coercer(type_a) { |v| "from-a:#{v}" }
    end
    sub_b = Class.new(TypedFormModel::Base) do
      register_coercer(type_b) { |v| "from-b:#{v}" }
    end

    # `coercer_registry` is private; reach it via send for this internal-isolation test.
    refute_nil sub_a.send(:coercer_registry).lookup(type_a), "sub_a should see its own type_a coercer"
    assert_nil sub_a.send(:coercer_registry).lookup(type_b), "sub_a must NOT see sub_b's type_b coercer"
    refute_nil sub_b.send(:coercer_registry).lookup(type_b), "sub_b should see its own type_b coercer"
    assert_nil sub_b.send(:coercer_registry).lookup(type_a), "sub_b must NOT see sub_a's type_a coercer"
  end

  # Fix 5: extract_form_params used to return plain Hash inputs unfiltered
  # (the downstream prop-name filter rescued correctness, but it's a
  # bug-magnet). Always wrap in ActionController::Parameters before
  # permitting so unknown keys are stripped at the extraction boundary.
  def test_from_params_with_extract_permits_a_plain_hash_via_action_controller_parameters
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ExtractPlainHashForm"
      prop :otp, String
    end
    key = form_class.form_name

    raw = {key => {"otp" => "123456", "danger" => "should-not-make-it-through"}}
    form = form_class.from_params(raw, extract: true)

    assert_equal "123456", form.otp
    refute_includes form.attributes.keys.map(&:to_s), "danger"
  end

  # Fix 6: Outside callers must not be able to skip transforms by passing
  # `__skip_transforms: true` to `Form.new(**permitted_params)` — only
  # `copy` (which knows the private SKIP_TRANSFORMS sentinel) may opt out.
  def test_passing_skip_transforms_true_from_outside_does_not_skip_transforms
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, transform: ->(v) { "#{v}_transformed" }
    end

    form = form_class.new(__skip_transforms: true, name: "raw")

    assert_equal "raw_transformed", form.name,
      "external callers passing __skip_transforms: true must NOT bypass transforms"
  end

  # --- Change 1: from_model / from_models with `props:` filtering ---

  def test_from_model_with_props_only_loads_named_props
    form_class = Class.new(TypedFormModel::Base) do
      include ::Literal::Types

      prop :name, String, default: proc { "default-name" }
      prop :age, Integer, default: proc { 0 }
      prop :email, _Nilable(String), default: proc { "default@example.com" }
    end
    record = Data.define(:name, :age, :email).new(name: "Alice", age: 30, email: "alice@example.com")

    form = form_class.from_model(record, props: [:name])

    assert_equal "Alice", form.name
    assert_equal 0, form.age, "age should fall back to default — not in `props:` allow-list"
    assert_equal "default@example.com", form.email, "email should fall back to default"
  end

  def test_from_models_with_props_skips_other_props_across_sources
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String, from: "user.name", default: proc { "default-name" }
      prop :age, Integer, from: "user.age", default: proc { 0 }
      prop :title, String, from: "profile.title", default: proc { "default-title" }
    end
    user = Data.define(:name, :age).new(name: "Alice", age: 30)
    profile = Data.define(:title).new(title: "CEO")

    form = form_class.from_models({user: user, profile: profile}, props: [:name, :title])

    assert_equal "Alice", form.name
    assert_equal 0, form.age, "age should be filtered out by `props:`"
    assert_equal "CEO", form.title
  end

  # --- Change 2: array-shaped props auto-default to [] ---

  def test_underscore_array_prop_without_default_initialises_to_empty_array
    form_class = Class.new(TypedFormModel::Base) do
      prop :tags, _Array(String)
    end

    assert_equal [], form_class.new.tags
  end

  def test_explicit_default_still_wins_over_auto_default_for_array
    form_class = Class.new(TypedFormModel::Base) do
      prop :tags, _Array(Symbol), default: -> { [:default] }
    end

    assert_equal [:default], form_class.new.tags
  end

  def test_plain_array_prop_without_default_initialises_to_empty_array
    form_class = Class.new(TypedFormModel::Base) do
      prop :tags, Array
    end

    assert_equal [], form_class.new.tags
  end

  def test_array_of_nested_form_prop_without_default_initialises_to_empty_array
    item_form_class = Class.new(TypedFormModel::Base) do
      def self.name = "ItemFormAutoDefault"
      prop :sku, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "ContainerAutoDefault"
    end
    container_class.prop :items, ::Literal::Types::ArrayType.new(item_form_class)

    assert_equal [], container_class.new.items
  end

  # --- Change 3: temporal coercer enhancements ---

  def test_date_coercer_converts_time_to_date_via_to_date
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    t = Time.utc(2026, 4, 28, 12, 0, 0)
    result = form_class.new(on: t).on

    assert_instance_of Date, result
    assert_equal Date.new(2026, 4, 28), result
  end

  def test_time_coercer_converts_date_to_time_via_to_time
    form_class = Class.new(TypedFormModel::Base) do
      prop :at, Time
    end

    d = Date.new(2026, 4, 28)
    result = form_class.new(at: d).at

    assert_kind_of Time, result
    assert_equal 2026, result.year
    assert_equal 4, result.month
    assert_equal 28, result.day
  end

  def test_datetime_coercer_converts_date_to_datetime
    form_class = Class.new(TypedFormModel::Base) do
      prop :at, DateTime
    end

    d = Date.new(2026, 4, 28)
    result = form_class.new(at: d).at

    assert_kind_of DateTime, result
    assert_equal 2026, result.year
    assert_equal 4, result.month
    assert_equal 28, result.day
  end

  def test_date_coercer_converts_datetime_to_date_via_to_date
    # DateTime < Date in Ruby's class hierarchy, so a naive `is_a?(Date)` check
    # would let DateTime instances pass through unchanged — leaking time-zone
    # information to consumers that asked for a plain Date.
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    dt = DateTime.new(2026, 4, 28, 12, 0, 0)
    result = form_class.new(on: dt).on

    assert_instance_of Date, result
    assert_equal Date.new(2026, 4, 28), result
  end

  def test_date_coercer_still_parses_iso_strings
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    assert_equal Date.new(2026, 4, 28), form_class.new(on: "2026-04-28").on
  end

  def test_date_coercer_returns_nil_for_unparseable_string
    form_class = Class.new(TypedFormModel::Base) do
      prop :on, Date
    end

    assert_nil form_class.new(on: "definitely-not-a-date").on
  end

  # --- Change 4: provided_keys and PATCH-correct merge ---

  def test_provided_keys_reflects_from_params_input
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :email, String
      prop :age, Integer
    end

    form = form_class.from_params({name: "Alice", email: nil})

    assert_includes form.provided_keys, :name
    assert_includes form.provided_keys, :email,
      "explicit nil counts as provided"
    refute_includes form.provided_keys, :age,
      "absent keys are NOT in provided_keys"
  end

  def test_provided_keys_reflects_from_model_props_read
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
      prop :email, String
    end
    record = Data.define(:name, :age).new(name: "Alice", age: 30)  # no email attr

    form = form_class.from_model(record)

    assert_includes form.provided_keys, :name
    assert_includes form.provided_keys, :age
    refute_includes form.provided_keys, :email,
      "props the source didn't have should not be in provided_keys"
  end

  def test_provided_keys_is_union_after_copy
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
      prop :email, String
    end

    base = form_class.new(name: "Alice")
    refute_includes base.provided_keys, :age

    copy = base.copy(age: 30)

    assert_includes copy.provided_keys, :name, "preserves base provided keys"
    assert_includes copy.provided_keys, :age, "adds copy override key"
    refute_includes copy.provided_keys, :email
  end

  def test_provided_keys_is_frozen
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    form = form_class.new(name: "Alice")

    assert_predicate form.provided_keys, :frozen?
  end

  def test_merge_with_explicit_nil_unsets_field
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :email, String
    end

    base = form_class.from_params({name: "Alice", email: "alice@example.com"})
    other = form_class.from_params({email: nil})

    merged = base.merge(other)

    assert_equal "Alice", merged.name, "name not provided in `other` — base wins"
    assert_nil merged.email, "explicit nil in `other.provided_keys` un-sets the field"
  end

  def test_merge_skips_fields_not_provided_in_other
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :email, String
    end

    base = form_class.from_params({name: "Alice", email: "alice@example.com"})
    other = form_class.from_params({name: "Bob"})

    merged = base.merge(other)

    assert_equal "Bob", merged.name, "other.name was provided"
    assert_equal "alice@example.com", merged.email, "other.email was not provided — base wins"
  end

  def test_external_provided_keys_kwarg_is_ignored_without_skip_transforms_sentinel
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
      prop :age, Integer
    end

    spoofed = ::Set[:age]
    form = form_class.new(__provided_keys: spoofed, name: "Alice")

    assert_equal ::Set[:name], form.provided_keys,
      "external `__provided_keys` must be discarded without the SKIP_TRANSFORMS sentinel"
  end

  # --- Change 5: surface trim ---

  def test_attribute_names_class_method_is_removed
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    refute_respond_to form_class, :attribute_names
  end

  def test_to_key_instance_method_is_removed
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    refute_respond_to form_class.new(name: "x"), :to_key
  end

  def test_plus_alias_for_merge_is_removed
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    refute_respond_to form_class.new(name: "x"), :+
  end

  def test_persisted_alias_without_question_mark_is_removed
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    refute_respond_to form_class.new(name: "x"), :persisted
    assert_respond_to form_class.new(name: "x"), :persisted?,
      "the predicate form must remain"
  end

  # --- Change 6: property alias dropped ---

  def test_property_class_method_is_no_longer_an_alias_for_prop
    form_class = Class.new(TypedFormModel::Base)

    refute_respond_to form_class, :property
  end

  # --- Review fix: predicates for explicit _Nilable wrappers ---

  def test_explicit_nilable_boolean_prop_still_defines_predicate
    form_class = Class.new(TypedFormModel::Base) do
      prop :flag, _Nilable(_Boolean)
    end

    instance = form_class.new(flag: true)
    assert_respond_to instance, :flag?
    assert_equal true, instance.flag?
    assert_equal false, form_class.new.flag?
  end

  def test_explicit_nilable_nested_form_prop_still_defines_attributes_setter
    nested_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeNestedForm"
      prop :name, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeContainer"
      prop :nested, _Nilable(nested_class)
    end

    assert_respond_to container_class.new, :nested_attributes=
  end

  def test_explicit_nilable_array_of_nested_forms_still_defines_attributes_setter
    nested_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeNestedItem"
      prop :name, String
    end
    container_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeArrayContainer"
      prop :items, _Nilable(_Array(nested_class))
    end

    assert_respond_to container_class.new, :items_attributes=
  end

  # --- Review fix: TimeWithZone passthrough on Time props ---

  def test_time_prop_preserves_active_support_time_with_zone
    form_class = Class.new(TypedFormModel::Base) do
      prop :at, Time
    end

    Time.use_zone("America/New_York") do
      twz = Time.zone.parse("2026-04-29T10:00:00")
      result = form_class.new(at: twz).at

      assert_kind_of ::ActiveSupport::TimeWithZone, result,
        "TimeWithZone should pass through unchanged so the explicit zone isn't dropped"
      assert_equal twz, result
    end
  end

  # --- Review fix: from: regex tightening ---

  def test_rejects_from_kwarg_with_whitespace_in_segments
    error = assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: " user.role_id "
      end
    end
    assert_match(/from:/, error.message)
  end

  def test_rejects_from_kwarg_with_numeric_segments
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: "1.2"
      end
    end
  end

  def test_rejects_from_kwarg_with_inner_whitespace
    assert_raises(ArgumentError) do
      Class.new(TypedFormModel::Base) do
        prop :role_id, Integer, from: "user .role_id"
      end
    end
  end

  # --- Review fix: from_model props: typo validation ---

  def test_from_model_props_rejects_undeclared_prop_name
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeFormForPropsCheck"
      prop :name, String
      prop :role, String
    end
    record = Data.define(:name, :role).new(name: "Alice", role: "admin")

    error = assert_raises(ArgumentError) do
      form_class.from_model(record, props: [:name, :typo])
    end
    assert_match(/typo/, error.message)
    assert_match(/undeclared/, error.message)
  end

  def test_from_models_props_rejects_undeclared_prop_name
    form_class = Class.new(TypedFormModel::Base) do
      def self.name = "FakeFormForFromModelsPropsCheck"
      prop :name, String, from: "user.name"
    end

    error = assert_raises(ArgumentError) do
      form_class.from_models({user: Data.define(:name).new(name: "x")}, props: [:typo])
    end
    assert_match(/typo/, error.message)
  end

  # --- Review fix: internal class methods are private ---

  def test_internal_class_methods_are_private
    form_class = Class.new(TypedFormModel::Base) do
      prop :name, String
    end

    refute form_class.respond_to?(:apply_transforms),
      "apply_transforms should be private_class_method"
    refute form_class.respond_to?(:prop_metadata_registry),
      "prop_metadata_registry should be private_class_method"
    refute form_class.respond_to?(:coercer_registry),
      "coercer_registry should be private_class_method"
    # Documented public surface still reachable
    assert form_class.respond_to?(:register_coercer)
    assert form_class.respond_to?(:prop_metadata_for)
  end
end
