
# simple
# shows simple call of xopt

require "../xopt.rb"

opt = Xopt.getopt(%w"login n file|f=/dev/null sepp|s senf|s")
if opt.failed?
  $stderr.puts "The given options are unfortunately faulty."
  exit 1      
end

puts "List of all options:"
opt.to_hash.each do |k,v|
   puts "#{k}:\t #{v}"
end

puts "\nRemaining arguments: #{ARGV.inspect}"
