# `typed_form_model`

Typed Rails form objects on top of `Literal::Struct` and `ActiveModel::Validations`.

---

## Tradeoffs

- Coercion is always on. There is no opt-out at the prop level except by declaring the type as `String`.
- Errors during coercion (`"abc"` to Integer) silently produce `nil` and rely on `validates :x, presence: true` to reject. If you want strict parsing, this is the wrong library.
- Validation is `ActiveModel::Validations`, not a schema. If you want a typed pipeline of input contracts independent of Rails, use `dry-validation`.

---

## Installation

```ruby
# Gemfile
gem "typed_form_model"
```

```bash
bundle install
```

Requires Rails ≥ 8.0 and Ruby ≥ 3.2. Hard dependencies: `literal`, `activemodel`, `activesupport`, `actionpack`, `bigdecimal`.

---

## 30-second quickstart

```ruby
# app/forms/contact_request_form.rb
class ContactRequestForm < TypedFormModel::Base
  prop :email, String
  prop :message, String

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :message, presence: true, length: { minimum: 10 }
end
```

```ruby
# app/controllers/contact_requests_controller.rb
class ContactRequestsController < ApplicationController
  def new
    @form = ContactRequestForm.new
  end

  def create
    @form = ContactRequestForm.from_params(params, extract: true)
    if @form.valid?
      ContactRequest.create!(@form.attributes)
      redirect_to thank_you_path
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

```erb
<%= form_with model: @form, url: contact_requests_path do |f| %>
  <%= f.email_field :email %>
  <%= f.text_area :message %>
  <%= f.submit %>
<% end %>
```

`from_params(params, extract: true)` pulls `params[:contact_request_form]`, applies the strong-params whitelist derived from prop declarations, coerces, and returns a form instance.

---

## Core concepts

### Props

`prop name, type, **options`. Type is a Ruby class (`String`, `Integer`, `Date`, `BigDecimal`, `Symbol`) or a `Literal::Types` term (`_Boolean`, `_Array(T)`, `_Nilable(T)`, `_Any`). A prop without `default:` is implicitly nilable with default `nil`. Array-shaped props (`Array`, `_Array(T)`) auto-default to `[]` instead.

### Coercion

Always on. `""` to `Integer` becomes `nil`. `"123"` to `Integer` becomes `123`. `"true"`/`"1"`/`1` to `_Boolean` becomes `true`. ISO strings to `Date`/`Time`/`DateTime` are parsed. Unparseable values become `nil` rather than raising — validations are responsible for catching them.

### Blank-to-nil

The default. `""` becomes `nil` for String/Integer/Float/etc. props. Disabled per-prop with `blank_to_nil: false` (e.g. when you want to distinguish "user typed an empty string" from "field absent"). Forced off for `_Boolean` and array types — `[]` is not `nil`, and `""` for a boolean has its own coercion.

### Defaults

`default: literal_value` or `default: proc { ... }`. Use a proc for mutable defaults (`default: proc { [] }`) — a literal `[]` is shared across instances. Procs fire when the key is absent from the input, not when the value is `nil`.

### Validations

Standard `ActiveModel::Validations`. `valid?`, `errors`, `validate`, `validates_with`. Forms include `ActiveModel::Validations::Callbacks` (`before_validation`).

### Model mapping

One annotation on a prop, in three shapes:

- **No `from:`** — the prop name is the attribute name. `from_model(record)` reads `record.<prop_name>`. Bag-of-attributes only — not in any multi-source slice.
- **`from: :other_name`** — single-source rename. `from_model(record)` reads `record.other_name` and exposes it as `prop_name`. Not in any multi-source slice.
- **`from: "source.attribute"`** — multi-source. The first segment names the source (matches the kwarg key in `from_models(source: ...)` and `to_model_attributes(:source)`); the second names the attribute on that source. Exactly one dot.

`from_models(user: u, profile: p)` reads each prop from its tagged source — the kwarg keys match the source segments of the dotted `from:` strings. `to_model_attributes(:user)` returns the slice for that source.

### Persisted flag

`form.persisted?` is a user-supplied boolean passed at construction (`from_params(params, persisted: true)` or `from_models(..., persisted: true)`). Exists so you can branch in validations or rendering between create and update without sniffing for an `id`.

### Context

`form.context` is a user-supplied `Hash` set at construction. The arity-2 form of `transform:` receives it: `transform: ->(value, context) { ... }`. Useful for tenant-scoped or current-user-aware coercion.

---

## Mapping forms ↔ models

Real example: an admin user is split across three records — a `Admin`, an `Account` (Devise auth), and a `UserProfile`. A single edit form reads from all three and writes back to all three.

```ruby
class AdminUserForm < TypedFormModel::Base
  prop :email,             String, from: "account.email"
  prop :unconfirmed_email, String, from: "account.unconfirmed_email"
  prop :role,              String, from: "admin.role"
  prop :first_name,        String, from: "admin.first_name"
  prop :last_name,         String, from: "admin.last_name"
  prop :position_name,     String, from: "user_profile.position_name"
  prop :phone_number,      String, from: "user_profile.phone_number"
  prop :bio,               String, from: "user_profile.bio"
  prop :profile_image,     _Any,   from: "user_profile.profile_image"

  validates :first_name, :last_name, :email, presence: true
end
```

The first segment of each dotted `from:` (`account`, `admin`, `user_profile`) is the source key; the second is the attribute name on that source. Renaming a single attribute on the source is also fine: `prop :user_job_title, String, from: "user_profile.position_name"` exposes `user_job_title` on the form but reads/writes `position_name` on the `:user_profile` record.

Build from records:

```ruby
@form = AdminUserForm.from_models(
  admin:        @admin,
  account:      @admin.account,
  user_profile: @admin.user_profile
)
```

`from_model(record)` is the single-source variant — the source segment of dotted `from:` is ignored and every prop pulls from `record` (using the `from:` rename if set). Use it for the simple edit-form case.

Extract per-model attributes for save:

```ruby
@form.to_model_attributes(:account)      # => { email: "...", unconfirmed_email: "..." }
@form.to_model_attributes(:user_profile) # => { position_name: "...", phone_number: "...", ... }
@form.to_model_attributes(:admin, except: [:role]) # remove keys after `from:` renaming
```

`to_model_attributes` skips `nil` values. Forms don't own IDs; `:id` is excluded unless you call `attributes(include_id: true)`.

---

## Nested forms

Declare the nested type and the array variant works the same way:

```ruby
class BidItemForm < TypedFormModel::Base
  prop :specified_product_id, Integer
  prop :quantity, Numeric
  prop :proposed_unit_price_dollars, Numeric
  prop :removed, _Boolean, default: false

  validates :specified_product_id, presence: true
end

class BidSubmissionForm < TypedFormModel::Base
  prop :preferred_delivery_date, Date
  prop :notes, String
  prop :items, _Array(BidItemForm)  # array-shaped, auto-defaults to []

  validate :at_least_one_item_with_quantity

  private

  def at_least_one_item_with_quantity
    return if items.any? { |i| i.quantity.to_i > 0 && !i.removed }
    errors.add(:items, "must have at least one item with quantity")
  end
end
```

Three things happen automatically:

1. **FormBuilder support.** `typed_form_model` defines a no-op `items_attributes=` setter so `form_with model: @bid` followed by `f.fields_for :items` works without `accepts_nested_attributes_for`.
2. **Param coercion.** Hashes nested under `items_attributes` (Rails' default key for `fields_for`) are coerced into `BidItemForm` instances by the array coercer. Existing instances pass through. Active Record records get fed through `BidItemForm.from_model`.
3. **Strong params.** `BidSubmissionForm.keys_for_permit` recurses into nested form props and produces the right `permit(...)` spec — you get this from `from_params(..., extract: true)` for free, or call it directly:

```ruby
params.require(:bid_submission_form).permit(BidSubmissionForm.keys_for_permit)
```

For nested-form validation cascade (parent invalid if child invalid), use `validates_nested :items`. Each child error propagates to the parent under the parent attribute path, using the child's `full_message`. For array-shaped nested props, every invalid item contributes its errors as separate entries under the parent attribute (one parent error per `(item, child error)` pair). `nil` children and children that respond `true` to `marked_for_destruction?` are skipped.

Single nested form (not array): `prop :address, AddressForm`. Same rules, but the auto-defined setter is `address_attributes=`.

---

## Custom coercion

Two ways. Use the right one.

### Block on `prop` — for one-off transforms

```ruby
prop :allergens, Array, blank_to_nil: true do |v|
  v.is_a?(String) ? v.split(",") : v
end

prop :product_tag_ids, Array do |v|
  v.to_a.map { |item| item.respond_to?(:id) ? item.id : item.to_i }
end
```

The block replaces the default coercer for that prop. Use this when the rule is local to one form.

### `register_coercer` — for a custom type used across props

```ruby
class InvoiceForm < TypedFormModel::Base
  register_coercer(Money) do |v|
    case v
    when Money then v
    when String, Numeric then Money.parse(v)
    end
  end

  prop :subtotal, Money
  prop :tax,      Money
  prop :total,    Money
end
```

Subclasses inherit the parent class's registry. Useful for value objects (`Money`, `Tel`, `Postcode`) shared across many forms — register once in a base class.

Built-in coercers (`Integer`, `Float`, `BigDecimal`, `Numeric`, `String`, `Symbol`, `Date`, `Time`, `DateTime`, `_Boolean`, nested forms, arrays of forms) are always there as fallback. Custom registrations take precedence.

---

## Transforms vs validations vs coercion

Common confusion. The order is fixed:

1. **`transform:` runs first**, on the raw input value, before coercion. Receives the raw value (and optionally `context`). Use this when the input shape needs reshaping before the type system sees it (e.g. `"$12.34"` → `"12.34"`).
2. **Coercion runs next**, on the transformed value. String → Integer/Float/Date, blank → nil, Hash → nested form. Coercion failures yield `nil`.
3. **Validations run last**, on the coerced value, when you call `valid?`. Use these to reject `nil`, enforce ranges, format-match, etc.

Rule of thumb:

- Reshape the raw input → `transform:`.
- Convert primitive types or instantiate value objects → coercion (built-in or custom).
- Reject bad data → `validates`.

Don't put parsing in validations and don't put presence checks in transforms.

---

## Controller pattern

The canonical controller pair (create + update) for a form mapped to a single AR model. Adapt for multi-model forms by calling `to_model_attributes(:name)` per model.

```ruby
class EntityGroupsController < ApplicationController
  def new
    @form = EntityGroupForm.new
  end

  def create
    @form = EntityGroupForm.from_params(params, extract: true)
    if @form.valid?
      @entity_group = EntityGroup.create!(@form.attributes)
      redirect_to @entity_group, notice: "Created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @entity_group = EntityGroup.find(params[:id])
    @form = EntityGroupForm.from_model(@entity_group, persisted: true)
  end

  def update
    @entity_group = EntityGroup.find(params[:id])
    @form = EntityGroupForm.from_params(params, persisted: true, extract: true)
    if @form.valid?
      @entity_group.update!(@form.attributes)
      redirect_to @entity_group, notice: "Updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
```

Multi-model variant (the admin-user controller pattern):

```ruby
def update
  @form = AdminUserForm.from_params(params, persisted: true, extract: true)
  if @form.valid?
    Admin.transaction do
      @admin.update!(@form.to_model_attributes(:admin))
      @admin.account.update!(@form.to_model_attributes(:account))
      @admin.user_profile.update!(@form.to_model_attributes(:user_profile))
    end
    redirect_to @admin
  else
    render :edit, status: :unprocessable_entity
  end
end

def edit
  @form = AdminUserForm.from_models(
    admin:        @admin,
    account:      @admin.account,
    user_profile: @admin.user_profile
  )
end
```

`extract: true` does the work of `params.require(:form_name).permit(Form.keys_for_permit)`. Skip it if you want to permit manually or build from a Hash.

---

## API reference

### Class methods

| Method | Description |
|---|---|
| `prop(name, type, **opts, &block)` | Declare a typed prop. Options: `from:` (Symbol or `"source.attribute"` String), `default:`, `blank_to_nil:`, `transform:`. Optional block overrides the coercer for this prop. |
| `from_params(raw, persisted: false, extract: false)` | Build an instance from `Hash` or `ActionController::Parameters`. `extract: true` unwraps `params[form_name]` and permits via `keys_for_permit`. |
| `from_model(record, persisted: true, context: {}, props: nil)` | Build from one source record. The source segment of dotted `from:` is ignored; every prop pulls from `record` using its `from:` rename (or the prop name). `props:` (Array of Symbols) restricts which props are pulled. |
| `from_models(sources = nil, persisted: true, context: {}, props: nil, **kwargs)` | Build from multiple records keyed by the source segment of dotted `from:`. Accepts `from_models(user: u, profile: p)` or an explicit hash — kwarg keys match those source segments. `props:` restricts which props are pulled across sources. |
| `keys_for_permit` | Strong-params whitelist spec (recurses into nested-form props). |
| `register_coercer(type, &block)` | Register a custom coercer for `type` on this class (and subclasses). |
| `validates_nested(*attrs)` | Cascade validation: parent invalid if any named nested-form prop (single or array) is invalid. Propagates each child error to the parent under the parent attribute path with the child's `full_message`. |
| `form_name` | `model_name.param_key` — the key used in form builder URLs and `extract:`. |
| `prop_metadata_for(name)` | Internal — read the parsed `from:` / `transform:` metadata for a prop. |
| `coercer_registry` | Internal — the per-class registry; subclasses inherit. |

### Instance methods

| Method | Description |
|---|---|
| `persisted?` | The user-supplied flag from construction. |
| `context` | The user-supplied `Hash` from construction. |
| `provided_keys` | Frozen `Set<Symbol>` of prop names explicitly provided at construction. Used by `merge`. |
| `attributes(include_id: false)` | `HashWithIndifferentAccess` of non-`nil` props. |
| `to_hash` / `to_h` | Plain `Hash` (symbol keys) of all props including `nil`s. |
| `to_params` | `{form_name => attributes.to_h}` — the inverse of `from_params(extract: true)`. |
| `to_model_attributes(model_name, except: [])` | `HashWithIndifferentAccess` of props whose dotted `from:` source segment matches `model_name`, with attribute renaming applied. |
| `[](key)` | Indifferent attribute access. `form[:email] == form["email"]`. |
| `valid?` / `errors` / `validate` | Standard `ActiveModel::Validations`. |
| `copy(**overrides)` | New instance with the given props overridden. Skips re-running `transform:`. `provided_keys` becomes `self.provided_keys ∪ overrides.keys`. |
| `merge(other)` | Layer another form of the same class on top. Keys in `other.provided_keys` win, **including explicit `nil`** (un-sets the field). Keys absent from `other.provided_keys` leave `self`'s value untouched — supports PATCH semantics. |
| `cache_key` | Stable hash of attributes — for `cache` blocks. |
| `==` / `eql?` / `hash` | Value equality on class + `to_hash`. |
| `as_json(opts = {})` | `to_hash.as_json(opts)`. |

### Rejected options

These raise `ArgumentError` at class-definition time with a remediation hint:

- `optional:` — use `_Nilable(Type)` and omit `default:`.
- `allow_nil:` — use `_Nilable(Type)`; presence is a validation concern.
- `allow_blank:` — use `validates :x, presence: true`.
- `in:` — use `validates :x, inclusion: { in: [...] }`.

---

## What this does NOT do

- It is not a validation DSL replacement. It uses `ActiveModel::Validations`. If you want predicate logic, schema composition, and structured failure values, use `dry-validation`.
- It is not a serializer. `as_json` is convenience only. For API responses use a real serializer.
- It is not bound to ActiveRecord. `from_model` calls `record.public_send(attr)` and `to_model_attributes` returns a Hash. You can use it with any object that exposes the right readers.
- It is not a save layer. There is no `form.save`. You write `Model.create!(form.attributes)` or `model.update!(form.to_model_attributes(:x))` yourself, in a transaction if needed.
- It is not a parser. Bad input becomes `nil`; rejection is a validation concern.

---

## Stability / status

1.0. The public API reflects what is in production use across ~80 forms in the parent application. SemVer applies — breaking changes will bump the major version.

---

## Contributing & development

```bash
bundle install              # install dependencies
bundle exec rake test       # run the suite (Minitest)
```

PRs welcome. Please:

- Add tests in `test/` covering the new behaviour.
- Update the README and `CHANGELOG.md` for any public-API change.
- Keep new features behind explicit prop options — coercion-by-default is a property of this gem and changes to ordering or invariants need discussion first.

---

## License

MIT. See `LICENSE.txt`.
