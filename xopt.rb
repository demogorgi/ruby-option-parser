
# xopt.rb, Version 0.60
# August 2019

# Simple class to evaluate command line options. 

class Xopt

	#
	# Evaluates the options specified in the first argument. Returns 
	# object of the class Xopt that contains all options. Removes the 
	# found options from the second argument.
	#
	def self.getopt(opt_defs, a=ARGV)
		new(opt_defs).get(a)
	end

	#
	# The method new receives the optional argument Array with 
	# options to be added
	#
	def initialize(opt_defs=[])
		# Class-wide properties
		@cluster_ok       = true  # Cluster allowed
		@last_only        = true  # Argument only for last cluster option
		@space_ok         = true  # Space between option and argument ok
		@get_all          = false # Evaluation takes place for entire ARGV
		@ignore_unknown   = false # Unknown options are silently removed
		@gnuish           = false # Single-letter options only in cluster ok
		@endopts          = %w(--) # Evaluation ends after one of these words
		@cluster_prefixes = %w(-)  # these prefixes introduce clustered options
		@plain_option     = BoolOption     # Standard option without argument
		@value_option     = ArgumentOption # Standard option with argument

		# Options-local properties
		@case_sensitive  = true  # Upper/lower case is distinguished
		@abbrev_ok       = true  # Abbreviations allowed
		@prefixes            = %w(-- -) # these prefixes introduce options
		@separators          = %w(=) # these separators separate an option from its value
		@cluster_separators  = ['=', ''] 

		defaults
		@special_class = get_special_classes # Hash of all special classes
		@option = Hash.new
		@failure = nil
		add opt_defs
	end

	#
	# Adds options from array argument to self.
	# Is called by initialize if necessary, return value self.
	#
	def add(opt_defs)
		opt_defs.each do |opt_def|
			klass, body, default = parse_def opt_def
			name, aliases = split_body body
			new_opt = create_opt(klass, name, aliases, default)
			add_raw new_opt
		end
		self
	end

	#
	# Segregates options from argument and sets value of option in self.
	# Return value self.
	#
	def get(list=ARGV)
		@failure = nil
		i = 0
		while i < list.length
			arg = list[i]
			if @endopts.include? arg
				list.slice!(i, 1)
				break
			end
			options = matching_opts(arg, list, i+1)

			if options.length == 1 # uniquely matching
				opt = options.first.dup
				opt.set(arg, list, i+1)
				t = opt.arg_taken
				if i + t >= list.length or (not @space_ok and t > 0)
					raise XoptError.new(:argument_required, [opt.name])
				else
					@option[opt.name] = opt
					list.slice!(i, 1+t)
				end
			elsif options.length > 1 # ambiguously fitting
				opt_names = options.collect { |o| o.name }
				raise XoptError.new(:ambiguous, opt_names)
			elsif @cluster_ok and s = strip_cluster(arg)
				get_cluster_option(arg, s, list, i)
				break if @failure
			elsif option_like? arg # unknown option
				if @ignore_unknown
					list.slice!(i, 1)
				else
					raise XoptError.new(:unknown, [])
				end
			else # normal argument
				if @get_all
					i += 1
				else
					break
				end
			end
		end
		self
	rescue XoptError => e
		@failure = Failure.new(e.kind, arg, e.options)
		self
	end

	#
	# Tests whether an error occurred when get was called.
	#
	def failed?
		not @failure.nil?
	end

	#
	# Returns nil or an error that occurred when get was called.
	#
	attr_reader :failure  

	#
	# Returns structure whose elements are the names of the options.
	# The values of the elements are the values of the options.
	#
	def to_struct
		values = @option.values.collect { |o| o.value }
		Struct.new(nil, *@option.keys).new(*values)
	end

	#
	# Returns a hash table whose keys are the names of the options.
	# The corresponding values are the values of the options.
	#
	def to_hash
		a = Hash.new
		@option.each_pair do |k, v|
			a[k] = v.value
		end
		a
	end

	#
	# Private helper methods for initialize
	#
	private
	def defaults
		# Used in derived classes to change features.
	end

	def get_special_classes
		# Returns hash of all classes derived from AbstractOption,
		# in which the constant SIG is not equal to nil.
		h = Hash.new
		self.class.constants.
			collect { |s| self.class.const_get(s) }.
			select  { |c| c.class == Class }.
			select  { |c| c.ancestors.include? AbstractOption }.
			each do |c|
				sig = c.const_get(:SIG)
				if sig
					h[sig] = c
				end  
			end
			h
	end

	#
	# Private helper methods for add
	#
	def parse_def(opt)
		# Determines for definition string: class, body and default.
		# The determined class is either a special one (by signature at the beginning),
		# a "value_option" (by a '=' in the string) or otherwise a "plain_option".
		klass = nil
		word = opt
		@special_class.keys.each do |sig|
			if opt.index(sig) == 0
				word = opt[sig.length .. -1]
				klass = @special_class[sig]
				break
			end
		end
		eqs = /=/
		if eqs.match word
			body, value = word.split(eqs, 2)
			value = nil if value.empty?
			klass ||= @value_option
		else
			body = word
			value = nil
			klass ||= @plain_option
		end
		[klass, body, value]
	end

	Tilde = '~'
	def split_body(body)
		# Splits body into main names and synonyms. The main name is always also 
		# a synonym unless preceded by a tilde. It is only parsed for synonyms,
		# but the main name is used to access the option in the program
		aliases = body.split "|"
		name = aliases.first
		if name.index(Tilde) == 0
			name.sub!(Tilde, '')
			aliases.shift
		end  
		[name, aliases]
	end

	def create_opt(klass, name, aliases, default)
		# Creates new option
		clusters = aliases.select { |n| n.length == 1 }
		shapes = []
		aliases.each do |n|
			next if @gnuish and n.length == 1
			shapes.push(*(@prefixes.collect { |p| [p, n] }))
		end
		klass.new(name, nil, shapes, clusters, @separators, 
			  @cluster_separators, @case_sensitive, @abbrev_ok, default)
	end

	def add_raw(opt)
		# Adds option to self, argument comes from one of the
		# option classes.
		@option[opt.name] = opt
		self
	end

	#
	# Private helper methods for get
	#
	def matching_opts(arg, list, i)
		# Returns field of all exactly or abbreviated matching options.
		m = @option.values.select { |o| o.match?(arg, list, i) == :exact }
		if m.empty?
			@option.values.select { |o| o.match?(arg, list, i) == :abbrev }
		else
			m
		end   
	end

	def strip_cluster(arg)
		# Returns the option string for possible option clusters without 
		# prefix, for all other options nil.
		excludes = @prefixes - @cluster_prefixes
		excludes.each do |p|
			return nil if arg.index(p) == 0 
		end
		prefs = @cluster_prefixes.select { |p| arg.index(p) == 0 }
		if (prefs).empty?
			nil
		else
			arg[prefs.first.length .. -1]
		end
	end

	def get_cluster_option(arg, rest, list, oi)
		# Evaluates option cluster. Sets values of all found options.
		ai = oi + 1
		copt = @option.dup
		begin
			until rest.empty?
				options = copt.values.select { |o| o.cluster_match?(rest, list, ai) }
				if options.length == 1
					opt = options.first.dup
					old_rest = rest
					rest = opt.cluster_set(rest, list, ai)
					t = opt.arg_taken
					if t > 0 and (not @space_ok or 
						      (@last_only and not rest.empty?))
						raise XoptError.new(:wrong_position, [opt.name])
					end 
					ai += t
					if ai > list.length
						rest = old_rest
						raise XoptError.new(:argument_required, [opt.name])
					end
					copt[opt.name] = opt
				elsif options.empty?
					if @ignore_unknown
						list.slice!(oi, 1)
						return
					else
						raise XoptError.new(:unknown, [])
					end
				else
					opt_names = options.collect { |o| o.name }
					raise XoptError.new(:ambiguous, opt_names)
				end
			end
		rescue XoptError => e
			@failure = Failure.new(e.kind, arg, e.options, rest[0,1], true)
		else
			@option.replace copt 
			list.slice!(oi...ai)
		end
	end

	def option_like?(w)
		# Tests if argument starts with an options prefix.
		not @prefixes.select { |p| w.index(p) == 0 }.empty?
	end

	#
	# Exception XoptError is only used internally and cathched by get.
	#
	class XoptError < StandardError
		def initialize(kind, options)
			super("invalid option (#{kind.to_s})")
			@kind = kind
			@options = options
		end
		attr_reader :kind, :options
	end

	#
	# If the evaluation is incorrect, the failure method returns an object 
	# of the class Failure, its methods type and occurrence of the error  
	# and specify affected options.
	#
	class Failure
		def initialize(kind, argument, options, part=nil, incluster=false)
			@kind = kind
			@argument = argument
			@options = options
			@part = part
			@incluster = incluster
		end
		attr_reader :kind, :argument, :options, :part
		def cluster?
			@incluster
		end  
	end

	#
	# Option classes
	#
	class AbstractOption
		# Abstract class from which all other option classes should inherit 
		# Provides all public methods required for options; except set.
		SIG = nil # is overwritten in all derived classes
		def initialize(name, value=nil, shapes=[], clusters=[], 
			       separators=[], cluster_separators=[], 
			       case_sensitive=true, abbrev_ok = true, 
			       str_default=nil)
			@name = name
			@value = (value.nil? ? default(str_default) : value)
			@shapes = shapes
			@clusters = clusters
			@separators = separators
			@cluster_separators = cluster_separators
			@case_sensitive = case_sensitive
			@abbrev_ok = abbrev_ok
			@arg_taken = 0
		end

		attr_reader :name, :arg_taken
		attr_accessor :value

		def match?(word, *)
			# Tests whether the first argument matches self.
			# Is called by Xopt#get.
			w = xcase(word)
			s = @shapes.collect { |t| t.join }
			if s.include? w
				:exact
			elsif not @abbrev_ok or s.select { |t| t.index(w) == 0 }.empty?
				nil
			else
				:abbrev
			end      
		end

		def cluster_match?(word, *)
		    # Tests if the first argument contains self
			# as part of an options cluster.
			@clusters.include?(xcase(word[0,1]))
		end

		def cluster_set(word, *a)
			# Sets value of self; called if self was found in an options cluster.
			# Return value is the remaining options cluster.
			set(word, *a)
			word[1..-1]
		end

		def default(*)
			# Can be overwritten with the required default value in derived classes.
			# Is called by initialize.
			nil
		end

		private
		def xcase(word)
			@case_sensitive ? word : word.downcase
		end

	end

	#
	# The four predefined option classes, further option classes are 
	# defined in ext_opt.rb
	# 

	#
	# Boolean option: Value wrong or true.
	#   
	class BoolOption < AbstractOption
		def default(*)
			false
		end

		def set(*)
			@value = true
		end
	end

	#
	# Integer option: Value 0, increased by 1 per occurrence.
	#
	class IntegerOption < AbstractOption
		SIG = '#'
		def default(s=nil)
			s ? s.to_i : 0
		end

		def set(*)
			@value += 1
		end
	end  

	#
	# Option with argument: Default nil, value is mandatory argument.
	#
	class ArgumentOption < AbstractOption
		def default(s=nil)
			s 
		end

		def match?(word, *)
			@preval = nil
			s = @shapes.collect { |p| fitting_shapes(p, word) }.compact.
				sort { |a,b| a[1].length <=> b[1].length }
			if s.empty?
				nil
			else
				modus, rest = s.first
				if rest.empty?
					modus
				else
					seps = @separators.select { |sep| rest.index(sep) == 0 }
					if seps.empty?
						nil
					else
						@preval = rest[seps.first.length .. -1]
						modus
					end
				end
			end   
		end

		def cluster_match?(arg, list, l)
			unless @clusters.include?(xcase(arg[0,1]))
				return false
			end
			b = arg[1..-1]
			if b.empty?
				@preval = nil
			else # do separator and value follow?
				s = @cluster_separators.select { |t| b.index(t) == 0 }
				if s.empty?
					@preval = nil
				else
					@preval = b[s.first.length .. -1]
				end   
			end
			true
		end

		def set(*a)
			iset(*a)
		end
		alias cluster_set set

		private
		def fitting_shapes(shape, arg)
			# Determines whether shape matches argument. If shape matches
			# the return value is pair from type of fit
			# and remaining argument, otherwise nil. Is called
			# from match.
			prefix, name = shape
			if arg.index(prefix) == 0
				rest = arg[prefix.length .. -1]
				irest = xcase rest
				if irest[0] != name[0]
					nil
				elsif irest.index(name) == 0
					[:exact, rest[name.length .. -1]]
				elsif @abbrev_ok
					i = 0
					while irest[i] == name[i]
						i += 1
					end
					[:abbrev, rest[i..-1]]
				end
			else
				nil
			end
		end

		def iset(arg, list, l)
			# Helper method for set and cluster_set.
			if @preval
				@value = @preval 
				@arg_taken = 0
				""
			else
				@value = list[l]
				@arg_taken = 1
				arg[1..-1]
			end
		end
	end

	#
	# Array options have a mandatory argument. All occurrences are collected
	# and delivered in an array. Default: empty array.
	#
	class ArrayOption < ArgumentOption
		SIG = '[]'
		def default(s=nil)
			s ? s.to_a : []
		end

		private
		def iset(*)
			val = @value
			a = super
			@value = val << @value
			a
		end
	end

	#
	# Derived evaluation classes
	# 

	#
	# For short options only clusters are possible, for long options
	# abbreviations are possible.
	#
	class Gnu < self
		def defaults
			@gnuish             = true
			@prefixes           = ['--']
			@cluster_separators = ['']
		end             
	end

	#
	# Classical pre-Gnu-Unix, cluster possible, no abbreviations.
	#
	class Classic < self
		def defaults
			@abbrev_ok          = false
			@prefixes           = ['-']
			@cluster_separators = ['']
		end             
	end

	#
	# Options can be anywhere, their arguments can only be defined by
	# a colon, no abbreviations.
	#
	class Dos < self
		def defaults
			@get_all            = true
			@abbrev_ok          = false
			@case_sensitive     = false
			@endopts            = []
			@prefixes           = %w(/)
			@cluster_prefixes   = %w(/)
			@separators         = %w(:)
			@cluster_separators = %w(:)
		end
	end
end
