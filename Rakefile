# frozen_string_literal: true

task default: :test

task :test do
  ruby "-Itest", "-e", "Dir['test/**/*_test.rb'].sort.each { |file| require File.expand_path(file) }"
end
