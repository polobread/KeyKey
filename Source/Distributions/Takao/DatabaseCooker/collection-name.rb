#!/usr/bin/env ruby -w
# [AUTO_HEADER]

# Preferences lists the collections by their Chinese name, and for the
# chichi77Collection files that name is already in the fourth column of every
# row, so it is read back out rather than kept in a second place that could
# drift. McBopomofo's phrase.occ has no such column and is named here.

STDOUT.set_encoding(Encoding::UTF_8)

if ARGV.size < 2
  STDERR.puts "usage: collection-name.rb <source file> <collection name> [> output.sql]"
  exit 1
end

path, collection = ARGV[0], ARGV[1]

display = nil
if path.end_with?(".tsv")
  File.open(path, "r:UTF-8") do |input|
    input.gets                        # header
    while (line = input.gets)
      fields = line.split("\t")
      next if fields.size < 4
      candidate = fields[3].strip
      next if candidate.empty?
      display = candidate
      break
    end
  end
end
display ||= "小麥"

order = collection == "McBopomofo" ? 0 : 1

puts "INSERT INTO collection_names VALUES('#{collection}', '#{display.gsub("'", "''")}', #{order});"
