# Changelog

## [1.0.0]

First release. Initial public extraction.

- Typed prop declarations via `Literal::Struct`.
- Blank-to-nil coercion (opt out per-prop via `blank_to_nil: false`).
- Nested forms and array-of-nested-forms with FormBuilder integration (auto `*_attributes=` setters).
- Multi-model attribute mapping via a single `from:` kwarg per prop — `from: :other_name` for single-source rename or `from: "source.attribute"` for dotted-path multi-source.
- `from_params` / `from_model` / `from_models` constructors with `props:` filtering.
- `keys_for_permit` for strong-params whitelist generation, including nested forms.
- `validates_nested` with child-error propagation under parent attribute paths.
- Custom coercer registration via `register_coercer(Type) { |v| ... }` with subclass inheritance.
- PATCH-correct `merge` via `provided_keys` tracking — explicit `nil` un-sets, missing keys preserve.
- Coercion: ISO date/time parsing, integer/float/numeric/BigDecimal, boolean (`""`/`"0"`/`"1"`/`"true"`/`"false"`/`0`/`1`), Symbol with 64-byte cap.

Hard runtime dependencies: `literal`, `activemodel`, `activesupport`, `actionpack`, `bigdecimal`.
