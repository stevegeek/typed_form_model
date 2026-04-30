# frozen_string_literal: true

require_relative "lib/typed_form_model/version"

Gem::Specification.new do |spec|
  spec.name = "typed_form_model"
  spec.version = TypedFormModel::VERSION
  spec.authors = ["Stephen Ierodiaconou"]
  spec.email = ["stevegeek@gmail.com"]

  spec.summary = "Typed Rails form objects on top of Literal::Struct and ActiveModel::Validations."
  spec.description = "Form-object base class for Rails: typed props with always-on coercion, blank-to-nil, " \
                     "nested forms, multi-model attribute mapping, and ActiveModel validations. Built on " \
                     "the Literal gem."
  spec.homepage = "https://github.com/stevegeek/typed_form_model"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    %w[README.md CHANGELOG.md LICENSE.txt] +
      Dir["lib/**/*.rb"]
  end
  spec.require_paths = ["lib"]

  # Runtime
  spec.add_dependency "literal", ">= 1.9"
  spec.add_dependency "activemodel", ">= 8.0"
  spec.add_dependency "activesupport", ">= 8.0"
  spec.add_dependency "actionpack", ">= 8.0"
  spec.add_dependency "bigdecimal"

  # Development
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
