#!/usr/bin/env ruby -w
# [AUTO_HEADER]

# Product display-name overrides shared by all frontends are read from
# AssociatedPhraseCollectionNames.tsv. Collections without an override keep
# the name from the fourth column of their TSV source.

STDOUT.set_encoding(Encoding::UTF_8)

if ARGV.size < 3
  STDERR.puts "usage: collection-name.rb <source file> <collection name> <display names.tsv> [> output.sql]"
  exit 1
end

path, collection, display_names_path = ARGV[0], ARGV[1], ARGV[2]

display_names = {}
File.open(display_names_path, "r:UTF-8") do |input|
  input.each_line.with_index do |line, index|
    next if index == 0
    fields = line.chomp.split("\t", -1)
    next if fields.size < 2
    source = fields[0].strip
    name = fields[1].strip
    display_names[source] = name unless source.empty? || name.empty?
  end
end

display = display_names[collection]
if !display && path.end_with?(".tsv")
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
display ||= collection

order = collection == "McBopomofo" ? 0 : 1

puts "INSERT INTO collection_names VALUES('#{collection}', '#{display.gsub("'", "''")}', #{order});"
