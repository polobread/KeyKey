#!/usr/bin/ruby

require "benchmark"

THRESHOLD = -6.0
MAX_LENGTH = 20

if ARGV.size < 3
  STDERR.puts "usage: AssociatedPhraseCooker.rb <source lm> <output sql> <collection name>"
  exit 1
end

COLLECTION = ARGV[2]

begin
  input = File.open(ARGV[0], "r")
rescue
  STDERR.puts "cannot open #{ARGV[0]}"
  exit 1
end

begin
  output = File.open(ARGV[1], "w")
rescue
  STDERR.puts "cannot open #{ARGV[1]}"
  exit 1
end

count = 0
max = 0
data = {}

bmark = Benchmark.measure do

while line = input.gets
  break if line =~ /1-gram/
end

banwords = %W{ 媽的 }
banexp = Regexp.new(banwords.join("|"))

while line = input.gets
  break if line =~ /2-gram/

  p = line.split(/\s+/)
  if p.size > 1
    freq = p[0].to_f
    str = p[1].unpack("U*")
    if str.size > 1 && str.size <= MAX_LENGTH && p[1] !~ banexp && freq > THRESHOLD
      fw = [str.shift].pack("U")
      rest = str.pack("U*")
      
      # if it's ineed a Chinese char
      if fw.bytesize == 3
        if data[fw]
          data[fw] << [rest, freq]
        else
          data[fw] = [[rest, freq]]
        end
      end
    end
  end
end

output.puts "BEGIN;"

data.keys.sort.each do |k|
  sorted = data[k].sort{|x, y| y[1] <=> x[1] }.map {|a| a[0] }
  
  # puts "#{k} => #{sorted.join(',')}"
  output.puts "INSERT INTO associated_phrases VALUES('#{k}', '#{sorted.join(',')}', '#{COLLECTION}');"
  count += sorted.size
  
  if sorted.size > max
    max = sorted.size
  end
end

end # bmark.do

output.puts "COMMIT;"

input.close
output.close
STDERR.puts "#{COLLECTION}: #{count} phrases, max per-keyword count: #{max}, average: #{count.to_f / data.size.to_f}, elapsed time: #{bmark.real}"

