#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates the Linux runtime table from the read-only OpenVanilla mapping.
# The generated table remains under the source table's BSD 3-Clause terms.

source = File.expand_path(
  '../../../ModulePackages/OVOFHanConvert/VXHCTC2SCTable.c', __dir__
)
output = File.expand_path('../data/tc2sc.cin', __dir__)

array_body = File.binread(source)[/\{(.*)\}/m, 1]
abort "Could not find the conversion table in #{source}" unless array_body

values = array_body.scan(/0x([0-9a-fA-F]+)/).flatten.map { |value| value.to_i(16) }
abort "Conversion table has an odd number of values" unless values.length.even?

pairs = values.each_slice(2).to_a
abort "Expected 3,058 explicit mappings, found #{pairs.length}" unless pairs.length == 3058
abort 'Conversion keys are not strictly sorted' unless pairs.each_cons(2).all? { |a, b| a[0] < b[0] }

lines = [
  '# Generated from VXHCTC2SCTable.c; do not edit by hand.',
  '# Copyright (c) 2004-2007 The OpenVanilla Project.',
  '# Derived from Encode::HanConvert 0.31 by Autrijus Tang.',
  '%gen_inp',
  '%chardef begin'
]
pairs.each do |traditional, simplified|
  lines << "#{[traditional].pack('U')}\t#{[simplified].pack('U')}"
end
lines << '%chardef end'

File.binwrite(output, "#{lines.join("\n")}\n")
