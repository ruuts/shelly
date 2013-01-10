require "rubygems"
require "core_ext/object"
require "core_ext/hash"
require "core_ext/string"

require "yaml"

require "shelly/helpers"
require "shelly/model"

module Shelly
  autoload :App, "shelly/app"
  autoload :Organization, "shelly/organization"
  autoload :Cloudfile, "shelly/cloudfile"
  autoload :Client, "shelly/client"
  autoload :StructureValidator, "shelly/structure_validator"
  autoload :User, "shelly/user"
  autoload :VERSION, "shelly/version"
end
