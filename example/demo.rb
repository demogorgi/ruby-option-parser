# demo
# shows how errors in get can be dealt with

require "../xopt.rb"

opt = Xopt::Gnu.new(%w"#verbose|v login n file|f=/dev/null sepp|s senf|se")
opt.get
if opt.failed?
  puts "The given options are unfortunately faulty."
  f = opt.failure
  puts case f.kind
        when :unknown
          "Option #{f.argument} unknown."
        when :cluster_unknown
	    "Character \"#{f.options}\" in options-cluster \"#{f.argument}\" cannot be assigned."
        when :ambiguous
          "Option #{f.argument} is ambiguous. Possible are #{f.options.join ", "}."
        when :ambiguous_cluster
          "Options-cluster #{f.argument} is ambiguous. Possible are #{f.options.join ", "}."
        when :argument_required
          "Missing argument for option #{f.argument} (recognized as #{f.options}) requires an argument."
        when :cluster_argument_required
          "Option `#{f.options}' in cluster `#{f.argument}' requires an argument."
        when :wrong_position
          "Option `#{f.options}' in cluster `#{f.argument}' has to be the last option in cluster."
        else
          "Kind of error (#{f.kind}) is unknown."
        end
  exit 1      
end

puts "List of all options:"
opt.to_hash.each do |k,v|
    puts "#{(k + ':').ljust(8, " ")} #{v}"
end

Opts = opt.to_struct
puts "\nRemaining arguments: #{ARGV.inspect}" if Opts.verbose > 0

