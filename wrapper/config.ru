ENV['RACK_ENV'] ||= 'test'

require 'rubygems'
require 'bundler'
Bundler.require :default, ENV['RACK_ENV'].to_sym

require File.expand_path('../lib/tokenex_gateway.rb', __FILE__)
run Sinatra::Application
