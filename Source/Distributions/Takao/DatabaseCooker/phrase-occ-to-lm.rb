#!/usr/bin/env ruby -w
# [AUTO_HEADER]

# AssociatedPhraseCooker reads an ARPA-style language model: a \1-gram: section
# of "log-probability word" lines. McBopomofo publishes raw occurrence counts
# as "word count", so the columns swap and the counts become log10 of their
# share of the total.
#
# The conversion is not cosmetic. AssociatedPhraseCooker's THRESHOLD is -6.0,
# written for log probabilities; feeding it counts would let every zero-count
# word through, since 0 is greater than -6.

require "set"

STDOUT.set_encoding(Encoding::UTF_8)

# Two input shapes. phrase.occ is "word count" separated by spaces;
# Categorized collection files are tab-separated with a header, where the first two
# columns are the word and its count and the rest is reading and category.

if ARGV.size < 1
  STDERR.puts "usage: phrase-occ-to-lm.rb <phrase.occ|collection.tsv> [exclusions] [> output.lm]"
  exit 1
end

# The people collections were lifted out of McBopomofo, so the names are in both
# and McBopomofo sorts first, which would hide the curated entry behind the
# general one. The vendored McBopomofo files stay as they are; the removal
# happens here.
EXCLUDED = if ARGV[1] && File.exist?(ARGV[1])
  File.readlines(ARGV[1], :encoding => "UTF-8").map { |line| line.strip }.reject(&:empty?).to_set
else
  Set.new
end

# The module looks the table up by the character just committed, so the first
# character has to be Han or the entry can never be reached. The rest is left
# alone: professional vocabulary is full of "F1分數" and "Adam最佳化器".
LEADS_WITH_HAN = /\A\p{Han}/
MAX_LENGTH = 20

rows = []
seen = {}
File.open(ARGV[0], "r:UTF-8") do |input|
  input.each_line do |line|
    fields = line.include?("\t") ? line.split("\t") : line.split
    word, count = fields[0], fields[1]
    next if word.nil? || count.nil?
    word = word.strip
    count = count.strip
    next unless count =~ /\A\d+\z/
    count = count.to_i
    next if count < 1
    next unless word =~ LEADS_WITH_HAN
    next unless (2..MAX_LENGTH).include?(word.length)
    next if EXCLUDED.include?(word)

    # A word listed twice in one collection would be emitted twice into the same
    # head character's candidate list. The higher count wins.
    if index = seen[word]
      rows[index][1] = count if count > rows[index][1]
      next
    end
    seen[word] = rows.size
    rows << [word, count]
  end
end

total = rows.inject(0) { |sum, (_, count)| sum + count }
if total.zero?
  STDERR.puts "no usable rows in #{ARGV[0]}"
  exit 1
end

puts "\\data\\"
puts "\\1-gram:"
rows.each do |word, count|
  puts format("%.4f %s", Math.log10(count.to_f / total), word)
end
puts "\\2-gram:"
puts "\\end\\"

STDERR.puts "phrase-occ-to-lm: #{rows.size} unigrams from #{ARGV[0]}" +
  (EXCLUDED.empty? ? "" : ", #{EXCLUDED.size} words excluded")
