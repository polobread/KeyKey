#!/usr/bin/env ruby

# Builds the language model used by OVIMSmartMandarin from the redistributable
# McBopomofo word counts and Bopomofo mappings. Optional UTF-8 corpora add a
# synthetic bigram model; each non-comment line is one sentence and may contain
# either whitespace-delimited words or unsegmented Traditional Chinese text.

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

MAX_PHRASE_LENGTH = 7
# The bootstrap corpus is synthetic. A strong unigram prior prevents a pair
# from overwhelming the much larger occurrence table; repeated template pairs
# are clipped separately below.
BIGRAM_PRIOR_STRENGTH = 1_000.0
# Template expansion creates useful new adjacent-word types, but its repetition
# count is not observed language frequency. Clip each synthetic pair so a
# repeated frame cannot dominate the unigram prior.
MAX_SYNTHETIC_BIGRAM_COUNT = 1
# Phrase counts provide pronunciation evidence for individual characters. Limit
# that evidence so overlapping dictionary phrases cannot erase a rare reading.
READING_EVIDENCE_PRIOR = 1_000.0
MAX_READING_EVIDENCE_WEIGHT = 0.85

COMPONENTS = {
  "ㄅ" => 0x0001, "ㄆ" => 0x0002, "ㄇ" => 0x0003, "ㄈ" => 0x0004,
  "ㄉ" => 0x0005, "ㄊ" => 0x0006, "ㄋ" => 0x0007, "ㄌ" => 0x0008,
  "ㄍ" => 0x0009, "ㄎ" => 0x000a, "ㄏ" => 0x000b,
  "ㄐ" => 0x000c, "ㄑ" => 0x000d, "ㄒ" => 0x000e,
  "ㄓ" => 0x000f, "ㄔ" => 0x0010, "ㄕ" => 0x0011, "ㄖ" => 0x0012,
  "ㄗ" => 0x0013, "ㄘ" => 0x0014, "ㄙ" => 0x0015,
  "ㄧ" => 0x0020, "ㄨ" => 0x0040, "ㄩ" => 0x0060,
  "ㄚ" => 0x0080, "ㄛ" => 0x0100, "ㄜ" => 0x0180, "ㄝ" => 0x0200,
  "ㄞ" => 0x0280, "ㄟ" => 0x0300, "ㄠ" => 0x0380, "ㄡ" => 0x0400,
  "ㄢ" => 0x0480, "ㄣ" => 0x0500, "ㄤ" => 0x0580, "ㄥ" => 0x0600,
  "ㄦ" => 0x0680,
  "ˊ" => 0x0800, "ˇ" => 0x1000, "ˋ" => 0x1800, "˙" => 0x2000
}.freeze

def absolute_order_string(syllable)
  components = syllable.each_char.map { |character| COMPONENTS[character] }
  if components.empty? || components.any?(&:nil?)
    raise ArgumentError, "invalid Bopomofo syllable: #{syllable.inspect}"
  end

  value = components.reduce(0, :|)
  consonant = value & 0x001f
  middle_vowel = ((value & 0x0060) >> 5) * 22
  vowel = ((value & 0x0780) >> 7) * 22 * 4
  tone = ((value & 0x3800) >> 11) * 22 * 4 * 14
  order = consonant + middle_vowel + vowel + tone

  [48 + (order % 79), 48 + (order / 79)].pack("CC")
end

def sql_string(value)
  "'#{value.gsub("'", "''")}'"
end

def segment_run(run, readings, probabilities)
  characters = run.each_char.to_a
  scores = Array.new(characters.length + 1, -Float::INFINITY)
  paths = Array.new(characters.length + 1)
  scores[0] = 0.0
  paths[0] = []

  characters.length.times do |position|
    next unless paths[position]

    matched = false
    1.upto([MAX_PHRASE_LENGTH, characters.length - position].min) do |length|
      word = characters[position, length].join
      next unless readings.key?(word)

      matched = true
      next_position = position + length
      score = scores[position] + probabilities.fetch(word)
      next unless score > scores[next_position]

      scores[next_position] = score
      paths[next_position] = paths[position] + [word]
    end

    # Unknown Han characters form a boundary instead of joining two unrelated
    # known phrases across an out-of-vocabulary character.
    next if matched

    next_position = position + 1
    next unless scores[position] > scores[next_position]

    scores[next_position] = scores[position]
    paths[next_position] = paths[position] + [nil]
  end

  paths[characters.length] || []
end

def sentence_sequences(line, readings, probabilities)
  text = line.strip
  return [] if text.empty? || text.start_with?("#")

  if text.match?(/\s/)
    tokens = text.split.flat_map do |field|
      field.scan(/\p{Han}+/).flat_map do |run|
        readings.key?(run) ? [run] : segment_run(run, readings, probabilities)
      end
    end
    return tokens.slice_when { |left, right| left.nil? || right.nil? }
                 .map { |sequence| sequence.compact }
                 .reject(&:empty?)
  end

  text.scan(/\p{Han}+/).map do |run|
    segment_run(run, readings, probabilities).compact
  end.reject(&:empty?)
end

if ARGV.length < 3
  warn "usage: SmartMandarinCooker.rb phrase.occ BPMFMappings.txt bpmf-absolute-order.cin " \
       "[--lexicon supplemental.tsv ...] [--lexicon-preserve-counts supplemental.tsv ...] [bigram-corpus ...]"
  exit 1
end

counts_path, mappings_path, bpmf_cin_path = ARGV.shift(3)
supplemental_lexicons = []
while ["--lexicon", "--lexicon-preserve-counts"].include?(ARGV.first)
  option = ARGV.shift
  path = ARGV.shift || abort("#{option} requires a path")
  supplemental_lexicons << [path, option == "--lexicon"]
end
bigram_corpus_paths = ARGV
counts = {}

File.foreach(counts_path, encoding: "UTF-8") do |line|
  word, raw_count = line.split
  next unless word && raw_count&.match?(/\A\d+\z/)

  count = raw_count.to_i
  next unless count.positive? && (1..MAX_PHRASE_LENGTH).cover?(word.length)

  counts[word] = count
end

readings = Hash.new { |hash, word| hash[word] = {} }
File.foreach(mappings_path, encoding: "UTF-8") do |line|
  fields = line.split
  word = fields.shift
  next unless word && counts.key?(word)
  next unless fields.length == word.length

  qstring = fields.map { |syllable| absolute_order_string(syllable) }.join
  readings[word][qstring] = true
end

inside_chardef = false
File.foreach(bpmf_cin_path, encoding: "UTF-8") do |line|
  if line.match?(/%chardef\s+begin/)
    inside_chardef = true
    next
  end
  if line.match?(/%chardef\s+end/)
    inside_chardef = false
    next
  end
  next unless inside_chardef

  qstring, word = line.split
  next unless qstring && word && word.length == 1 && counts.key?(word)

  readings[word][qstring] = true
end

supplemental_word_count = 0
supplemental_skipped_count = 0
supplemental_lexicons.each do |lexicon_path, override_existing_count|
  File.foreach(lexicon_path, encoding: "UTF-8") do |line|
    # Categorized associated-phrase TSVs have a fourth category column and
    # may have a fifth source column. Smart Mandarin only needs the first
    # three fields, while the project's small supplemental file has exactly
    # those three fields.
    word, raw_count, raw_reading = line.chomp.split("\t", -1).first(3)
    next unless word && raw_count&.match?(/\A\d+\z/) && raw_reading

    count = raw_count.to_i
    syllables = raw_reading.split
    unless count.positive? && (1..MAX_PHRASE_LENGTH).cover?(word.length) && syllables.length == word.length
      supplemental_skipped_count += 1
      next
    end

    begin
      qstring = syllables.map { |syllable| absolute_order_string(syllable) }.join
    rescue ArgumentError
      # Associated-phrase collections can contain mixed-script entries such as
      # 哆啦A夢. They remain valid for phrase lookup, but Smart Mandarin cannot
      # encode Latin letters or symbols as Bopomofo syllables.
      supplemental_skipped_count += 1
      next
    end
    if override_existing_count
      counts[word] = [counts.fetch(word, 0), count].max
    else
      counts[word] ||= count
    end
    readings[word][qstring] = true
    supplemental_word_count += 1
  end
end

total_count = readings.sum { |word, qstrings| qstrings.empty? ? 0 : counts.fetch(word) }
abort "Smart Mandarin source data contains no usable entries" if total_count.zero?

# phrase.occ counts are per written word, not per reading. Splitting a character's
# count evenly across every reading makes uncommon pronunciations of frequent
# characters outrank ordinary characters (for example 日/密 for ㄇㄧˋ).
# Multi-character entries give evidence of the reading used in context. Divide
# each phrase count among its own reading variants before collecting evidence.
reading_evidence = Hash.new { |hash, character| hash[character] = Hash.new(0.0) }
readings.each do |word, qstrings|
  next if word.length < 2 || qstrings.empty?

  characters = word.each_char.to_a
  occurrence_per_reading = counts.fetch(word).to_f / qstrings.length
  qstrings.each_key do |qstring|
    characters.each_with_index do |character, index|
      reading_evidence[character][qstring.byteslice(index * 2, 2)] += occurrence_per_reading
    end
  end
end

reading_weights = {}
readings.each do |word, qstrings|
  next unless word.length == 1 && qstrings.length > 1

  evidence = reading_evidence[word]
  total_evidence = qstrings.keys.sum { |qstring| evidence[qstring] }
  next if total_evidence.zero?

  # Phrase entries overlap, so their summed counts are not independent samples.
  # Use the character's own count to set confidence in the distribution.
  character_count = counts.fetch(word).to_f
  evidence_weight = [character_count / (character_count + READING_EVIDENCE_PRIOR),
                     MAX_READING_EVIDENCE_WEIGHT].min
  uniform_weight = (1.0 - evidence_weight) / qstrings.length
  reading_weights[word] = qstrings.keys.to_h do |qstring|
    [qstring, uniform_weight + evidence_weight * evidence[qstring] / total_evidence]
  end
end

reading_weight_for = lambda do |word, qstring|
  reading_weights[word]&.fetch(qstring) || 1.0 / readings.fetch(word).length
end

word_probabilities = {}
readings.each do |word, qstrings|
  next if qstrings.empty?

  word_probabilities[word] = Math.log10(counts.fetch(word).to_f / total_count)
end

bigram_counts = Hash.new(0)
outgoing_counts = Hash.new(0)
sentence_count = 0
token_count = 0
clipped_bigram_occurrence_count = 0

unless bigram_corpus_paths.empty?
  bigram_corpus_paths.each do |bigram_corpus_path|
    File.foreach(bigram_corpus_path, encoding: "UTF-8") do |line|
      sentence_sequences(line, readings, word_probabilities).each do |tokens|
        next if tokens.empty?

        sentence_count += 1
        token_count += tokens.length
        (["<s>"] + tokens + ["</s>"]).each_cons(2) do |previous, current|
          pair = [previous, current]
          if bigram_counts[pair] >= MAX_SYNTHETIC_BIGRAM_COUNT
            clipped_bigram_occurrence_count += 1
            next
          end

          bigram_counts[pair] += 1
          outgoing_counts[previous] += 1
        end
      end
    end
  end

  abort "Smart Mandarin bigram corpora contain no usable sentences" if sentence_count.zero?
end

backoff_for = lambda do |word|
  outgoing = outgoing_counts[word]
  outgoing.zero? ? 0.0 : Math.log10(BIGRAM_PRIOR_STRENGTH / (outgoing + BIGRAM_PRIOR_STRENGTH))
end

puts "BEGIN;"
puts "INSERT INTO unigrams VALUES ('*', '', -99.0, 0.0);"
puts "INSERT INTO unigrams VALUES ('!', '', 0.0, #{backoff_for.call("<s>")});"
puts "INSERT INTO unigrams VALUES ('$', '', 0.0, 0.0);"

row_count = 0
readings.each do |word, qstrings|
  next if qstrings.empty?

  backoff = backoff_for.call(word)
  qstrings.each_key do |qstring|
    probability = word_probabilities.fetch(word) + Math.log10(reading_weight_for.call(word, qstring))
    puts "INSERT INTO unigrams VALUES (#{sql_string(qstring)}, #{sql_string(word)}, #{probability}, #{backoff});"
    row_count += 1
  end
end

bigram_row_count = 0
bigram_counts.each do |(previous, current), count|
  previous_qstrings = previous == "<s>" ? ["!"] : readings.fetch(previous).keys
  current_qstrings = current == "</s>" ? ["$"] : readings.fetch(current).keys
  previous_text = previous == "<s>" ? "" : previous
  current_text = current == "</s>" ? "" : current

  current_probabilities = current_qstrings.to_h do |current_qstring|
    if current == "</s>"
      base_probability = sentence_count.to_f / (token_count + sentence_count)
      occurrence = count.to_f
    else
      reading_weight = reading_weight_for.call(current, current_qstring)
      base_probability = counts.fetch(current).to_f / total_count * reading_weight
      occurrence = count.to_f * reading_weight
    end
    conditional_probability =
      (occurrence + BIGRAM_PRIOR_STRENGTH * base_probability) /
      (outgoing_counts.fetch(previous) + BIGRAM_PRIOR_STRENGTH)
    [current_qstring, Math.log10(conditional_probability)]
  end

  previous_qstrings.each do |previous_qstring|
    current_qstrings.each do |current_qstring|
      combined_qstring = "#{previous_qstring} #{current_qstring}"
      puts "INSERT INTO bigrams VALUES (#{sql_string(combined_qstring)}, #{sql_string(previous_text)}, #{sql_string(current_text)}, #{current_probabilities.fetch(current_qstring)});"
      bigram_row_count += 1
    end
  end
end

puts "COMMIT;"
warn "SmartMandarinCooker: #{row_count} unigrams from #{readings.length} words; " \
     "#{bigram_row_count} bigrams from #{sentence_count} sentences and #{token_count} tokens; " \
     "prior strength #{BIGRAM_PRIOR_STRENGTH.to_i}, pair count capped at #{MAX_SYNTHETIC_BIGRAM_COUNT}, " \
     "#{clipped_bigram_occurrence_count} repeated occurrences clipped; " \
     "#{supplemental_word_count} supplemental lexicon entries, " \
     "#{supplemental_skipped_count} invalid supplemental entries skipped"
