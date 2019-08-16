
require "xopt.rb"

class Xopt

  #
  # Methods for advanced applications
  #
  
  def merge(other)
    dup.merge! other
  end
  
  def merge!(other)
    # Merges options into a different style
    other.options.each do |o|
      add_raw o
    end
  end
  
  def options
    # Returns all options, used by "merge!"
    @option.values
  end
  protected :options
  
  public :add_raw
 
  ## Test for this! When more suitable than RawBoolOption?
  def add_shapes(name, klass, default, shapes, clusters)
    # Creates option with predefined shapes
    opt = klass.new(name, default, shapes, clusters, 
                @separators, @cluster_separators,
                @case_sensitive)
    add_raw(opt)
  end
  
  def add_names(name, klass, default, names, clusters)
    # Creates option with default name
    shapes = []
    names.each do |n|
      shapes.push(*(@prefixes.collect { |p| [p, n] }))
    end
    add_shapes(name, klass, default, shapes, clusters)
  end
  
  #
  # Derived Evaluation Classes
  # 

  #
  # All cluster options can have arguments.
  #
  class Weird < self
    def defaults
      @last_only           = false
      @cluster_separators  = []
    end             
  end

  #
  # No spaces allowed for argument options.
  #
  class NoSpace < self
    def defaults
      @space_ok = false
    end             
  end

  #
  # Only spaces allowed in argument options
  #
  class NoSep < self
    def defaults
      @separators = []
      @cluster_separators  = []
    end             
  end

  #
  # No clusters, no shortcuts, no separators. Test!
  #
  class X11 < self
    def defaults
      @cluster_prefixes   = []
      @prefixes           = ['-']
      @separators         = []
    end
    
    def option_like?(w)
      super or w.index('+') == 0
    end            
  end


  #
  # Separator also for clusters only =
  #
  class Equal < self
    def defaults
      @cluster_separators = @separators
    end
    
  end


  #
  # a la cdrecord, options without arguments without - and with =.
  #
  class Cdrecord < self
    def defaults
      @space_ok           = false
      @abbrev_ok          = false
      @cluster_ok         = false
      @separators         = %w(=)
      @value_option       = CdrecordOption
    end             
  end

  ## here even more evaluations a la ...
  ## prboom, find, a2ps

  #
  # Value true (also for -), value false for +.
  #
  class PlusOption < AbstractOption
    SIG = '+'
    def initialize(*)
      super
      @value = true if @value.nil?
      t = @shapes.collect { |p,n| ['+', n] }
      (@shapes.push(*t)).uniq!
    end

    def set(w, *)
      @value = !(w.index('+') == 0)
    end
  end


  #
  # Value = Option including prefix.
  #
  class RegexOption < AbstractOption
    def initialize(name, regex)
      @name = name
      @regex = regex
      @value = nil
      @arg_taken = 0
    end

    def match?(arg, *)
      if @regex.match(arg)
        @preval = arg
        :exact
      else
        false
      end       
    end

    def cluster_match?(*)
      false
    end

    def set(*)
      @value = @preval
    end   
  end

  #
  # Value = Option including prefix.
  #
  class RawBoolOption < AbstractOption
    def initialize(name, patterns, clusters)
      @name = name
      @patterns = patterns
      @clusters = clusters
      @value = false
      #p  patterns
      @arg_taken = 0
    end

    def match?(arg, *)
      if @patterns.select { |p| p == arg }.empty?
        false
      else
        :exact
      end       
    end

    def cluster_match?(w, *)
      m = @clusters.select { |c| w.index(c) == 0 }
      if m.empty?
        false
      else
        @fit = m.sort { |a,b| a.length <=> b.length }.first
        true
      end
    end

    def set(w, *)
      @value = w
    end
    
    def cluster_set(w, *)
      @value = @fit
      w[@fit.length .. -1]
    end
  end

  #
  # Value false, true or number as argument.
  #
  class IntegerArgumentOption < ArgumentOption
    SIG = '=#'
    def default(*)
      false
    end

    def iset(arg, list, l)
      if @preval
        @value = @preval 
        @arg_taken = 0
        ""
      else
        v = list[l]
        if /^(-|\+)?\d+$/.match v
          @value = v
          @arg_taken = 1
        else
          @value = true
          @arg_taken = 0
        end   
        arg[1..-1]
      end
    end
  end  

  #
  # Value false, true or non-option as argument.
  #   
  class OptionalArgumentOption < ArgumentOption
    SIG = '=?'
    def default(*)
      false
    end

    def iset(arg, list, l)
      if @preval
        @value = @preval 
        @arg_taken = 0
        ""
      else
        v = list[l]
        if v.nil? or /^-/.match v
          @value = true
          @arg_taken = 0
        else
          @value = v
          @arg_taken = 1
        end   
        arg[1..-1]
      end
    end
  end  


  #
  # Value "yes" or "no", long form with argument, short without, automatic
  # Value "yes". Only works if @gnuish == true.
  #   
  class A2psStarOption < ArgumentOption
    SIG = '**'
    def default(s)
      s ? s : "no"
    end

    def cluster_set(word, *)
      @value = "yes"
      @arg_taken = 0
      word[1..-1]
    end
  end

  #
  # Shapes without prefix.
  #   
  class CdrecordOption < ArgumentOption
    SIG = '!CD!'
    def initialize(*)
      super
      @shapes.collect! { |p,v| ['', v] }
    end
  end

  #
  # Value Hash, takes two arguments each for Key/Value
  #   
  class HashOption < AbstractOption
    SIG = '{}'
    def default(*)
      Hash.new
    end

    def set(arg, list, i)
      @value[list[i]] = list[i+1]
      @arg_taken = 2
      arg[1..-1]
    end
  end

  #
  # Value false, all other arguments
  #   
  class LineOption < AbstractOption
    SIG = '!%'
    def set(arg, list, i)
      line = list[i..-1]
      if line.nil? or line.empty?
        @arg_taken = 1
      else
        @value = line
        @arg_taken = line.length
      end
    end
  end  

  #
  # Value false, all remaining arguments up to semicolon
  #   
  class FindExecOption < AbstractOption
    SIG = '!F!'
    def set(arg, list, i)
      @value = []
      @arg_taken = 0
      (i..list.length).each do |n|
        @arg_taken += 1
        if list[n] == ';'
          break
        else
          @value.push list[n]
        end
      end
    end
  end  

  #
  # Executes block when set
  # 
  class ProcOption < BoolOption
    SIG = '!&!'
    def add_proc(b)
       @proc = b
    end
       
    def set(*)
      @proc.call self if defined? @proc
      super
    end
  end
  
  public
  def add_block(name, &b)
    @option[name].add_proc b
  end
  
  #
  # Value is field with all arguments per occurrence.
  #
  class ArrayOption2 < AbstractOption
    SIG = '[2]'
    def initialize(name, value, *a)
      super    
      @value = [] if @value.nil?
      @x = ArgumentOption.new(name, value, *a)
    end
    
    def default(s=nil)
      s ? s.to_a : []
    end
    
    def match?(*a)
      @x.match?(*a)
    end

    def set(*a)
      @x.set(*a)
      @value << @x.value
      @arg_taken = @x.arg_taken
    end

    def cluster_match?(*a)
      @x.cluster_match?(*a)
    end

    def cluster_set(*a)
      a = @x.cluster_set(*a)
      @value << @x.value
      @arg_taken = @x.arg_taken
      a
    end
  end

  #
  # Value like BoolOption, but recognizes argument appended
  # by separator and reports errors.
  #
  class NoArgOption < ArgumentOption
    def default(*)
      false
    end
    def iset(arg, *)
      if @preval
        raise XoptError, :needless_argument, @shapes.first.last ## ?
      end
      @value = true
      arg[1..-1]
    end
  end
end
