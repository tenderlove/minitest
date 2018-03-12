gem "minitest" # ensure we're using gemified minitest, not system TODO: REMOVE?

require "minitest"
require "minitest/spec"
require "minitest/mock"
require "minitest/hell" if ENV["MT_HELL"]

Minitest.autorun
