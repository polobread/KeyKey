#!/usr/bin/env ruby

# Keep the Windows native database cooker and the macOS Smart Mandarin cooker
# on the same language-model source data and scoring algorithm.
require "rbconfig"

output, cooker, *inputs = ARGV
abort "usage: GenerateSmartMandarinSql.rb output.sql SmartMandarinCooker.rb inputs..." unless output && cooker && inputs.length >= 3

File.open(output, "wb") do |file|
  success = system(RbConfig.ruby, "-E", "UTF-8", cooker, *inputs, out: file)
  abort "SmartMandarinCooker failed" unless success
end
