# frozen_string_literal: true

require "active_model"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/hash/indifferent_access"
require "action_controller/metal/strong_parameters"
require "literal"
require "bigdecimal"
require "digest"

require "typed_form_model/version"
require "typed_form_model/prop_metadata"
require "typed_form_model/coercer_registry"
require "typed_form_model/params_loader"
require "typed_form_model/model_loader"
require "typed_form_model/model_attributes_extractor"
require "typed_form_model/strong_params_builder"
require "typed_form_model/nested_validator"
require "typed_form_model/base"
