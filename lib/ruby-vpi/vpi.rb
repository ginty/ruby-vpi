# A utility layer which transforms the VPI interface
# into one that is more suitable for Ruby.
#--
# Copyright 2006 Suraj N. Kurapati
# See the file named LICENSE for details.

class Object
  include Vpi
end

module Vpi
  # Number of bits in PLI_INT32.
  INTEGER_BITS  = 32

  # Lowest upper bound of PLI_INT32.
  INTEGER_LIMIT = 2 ** INTEGER_BITS

  # Bit-mask capable of capturing PLI_INT32.
  INTEGER_MASK  = INTEGER_LIMIT - 1


  ##############################################################################
  # handles
  ##############################################################################

  Handle = SWIG::TYPE_p_unsigned_int

  # A handle is an object inside a Verilog simulation (see
  # *vpiHandle* in IEEE Std.  1364-2005).  VPI types and
  # properties listed in ext/vpi_user.h can be specified by
  # their names (strings or symbols) or integer constants.
  #
  # = Example names
  # * "intVal"
  # * :intVal
  # * "vpiIntVal"
  # * :vpiIntVal
  # * "VpiIntVal"
  # * :VpiIntVal
  #
  # = Example constants
  # * VpiIntVal
  # * VpiModule
  # * VpiReg
  #
  class Handle
    undef type # used to access vpiType
    include Vpi

    # Tests if the logic value of this handle is unknown (x).
    def x?
      get_value(VpiHexStrVal) =~ /x/i
    end

    # Sets the logic value of this handle to unknown (x).
    def x!
      put_value('x', VpiHexStrVal)
    end

    # Tests if the logic value of this handle is high impedance (z).
    def z?
      get_value(VpiHexStrVal) =~ /z/i
    end

    # Sets the logic value of this handle to high impedance (z).
    def z!
      put_value('z', VpiHexStrVal)
    end

    # Tests if the logic value of this handle is at "logic high" level.
    def high?
      get_value(VpiIntVal) != 0
    end

    # Sets the logic value of this handle to "logic high" level.
    def high!
      put_value(1, VpiIntVal)
    end

    # Tests if the logic value of this handle is at "logic low" level.
    def low?
      get_value(VpiHexStrVal) =~ /^0+$/
    end

    # Sets the logic value of this handle to "logic low" level.
    def low!
      put_value(0, VpiIntVal)
    end


    #---------------------------------------------------------------------------
    # edge detection
    #---------------------------------------------------------------------------

    # Remember the current value as the "previous" value.
    def __edge__update_previous_value #:nodoc:
      @prev_val = get_value(VpiHexStrVal)
    end

    # Returns the previous value as a hex string.
    def prev_val_hex #:nodoc:
      @prev_val.to_s
    end

    # Returns the previous value as an integer.
    def prev_val_int #:nodoc:
      prev_val_hex.to_i(16)
    end

    private :prev_val_hex, :prev_val_int


    # create methods for detecting all kinds of edges
    vals  = %w[0 1 x z]
    edges = vals.map {|a| vals.map {|b| a + b}}.flatten

    edges.each do |edge|
      old, new = edge.split(//)

      old_int  = old =~ /[01]/
      new_int  = new =~ /[01]/

      old_read = old_int ? 'int' : 'hex'
      new_read = new_int ? 'VpiIntVal' : 'VpiHexStrVal'

      old_test = old_int ? "== #{old}" : "=~ /#{old}/i"
      new_test = new_int ? "== #{new}" : "=~ /#{new}/i"

      class_eval %{
        def edge_#{edge}?
          old = prev_val_#{old_read}
          new = get_value(#{new_read})

          old #{old_test} and new #{new_test}
        end
      }
    end


    alias posedge? edge_01?
    alias negedge? edge_10?

    # Tests if either a positive or negative edge has occurred.
    def edge?
      posedge? or negedge?
    end

    # Tests if the logic value of this handle has
    # changed since the last simulation time step.
    def value_changed?
      old = prev_val_hex
      new = get_value(VpiHexStrVal)

      old != new
    end


    #---------------------------------------------------------------------------
    # reading & writing values
    #---------------------------------------------------------------------------

    # Reads the value using the given
    # format (integer constant) and
    # returns a +S_vpi_value+ object.
    def get_value_wrapper aFormat
      val = S_vpi_value.new :format => aFormat
      vpi_get_value self, val
      val
    end

    # Reads the value using the given format (name or
    # integer constant) and returns it.  If a format is
    # not given, then it is assumed to be VpiIntVal.
    def get_value aFormat = VpiIntVal
      fmt = resolve_prop_type(aFormat)

      if fmt == VpiIntVal
        fmt = VpiHexStrVal
        val = get_value_wrapper(fmt)
        val[fmt].to_i(16)
      else
        val = get_value_wrapper(fmt)
        val[fmt]
      end

        # @size ||= vpi_get(VpiSize, self)

        # if @size < INTEGER_BITS
        #   val.value.integer.to_i
        # else
        #   get_value_wrapper(VpiHexStrVal).value.str.to_s.to_i(16)
        # end
    end

    # Writes the given value using the given format (name or integer
    # constant), time, and delay, and then returns the written value.
    #
    # * If a format is not given, then the Verilog simulator
    #   will attempt to determine the correct format.
    #
    def put_value aValue, aFormat = nil, aTime = nil, aDelay = VpiNoDelay
      if vpi_get(VpiType, self) == VpiNet
        aDelay = VpiForceFlag

        if driver = self[VpiDriver].find {|d| d.vpiType != VpiForce}
          warn "forcing value #{aValue.inspect} onto wire #{self} that is already driven by #{driver.inspect}"
        end
      end

      aFormat =
        if aFormat
          resolve_prop_type(aFormat)

        elsif aValue.respond_to? :to_int
          VpiIntVal

        elsif aValue.respond_to? :to_float
          VpiRealVal

        elsif aValue.respond_to? :to_str
          VpiStringVal

        elsif aValue.is_a? S_vpi_time
          VpiTimeVal

        elsif aValue.is_a? S_vpi_vecval
          VpiVectorVal

        elsif aValue.is_a? S_vpi_strengthval
          VpiStrengthVal

        else
          get_value_wrapper(VpiObjTypeVal).format
        end

      newVal = S_vpi_value.new(:format => aFormat)

      writtenVal =
        case aFormat
        when VpiBinStrVal, VpiOctStrVal, VpiDecStrVal, VpiHexStrVal, VpiStringVal
          newVal.value.str      = aValue.to_s

        when VpiScalarVal
          newVal.value.scalar   = aValue.to_i

        when VpiIntVal
          @size ||= vpi_get(VpiSize, self)

          if @size < INTEGER_BITS
            newVal.format        = VpiIntVal
            newVal.value.integer = aValue.to_i
          else
            newVal.format        = VpiHexStrVal
            newVal.value.str     = aValue.to_i.to_s(16)
          end

        when VpiRealVal
          newVal.value.real     = aValue.to_f

        when VpiTimeVal
          newVal.value.time     = aValue

        when VpiVectorVal
          newVal.value.vector   = aValue

        when VpiStrengthVal
          newVal.value.strength = aValue

        else
          raise "unknown S_vpi_value.format: #{newVal.format.inspect}"
        end

      vpi_put_value(self, newVal, aTime, aDelay)

      writtenVal
    end

    # Forces the given value (see arguments for #put_value) onto this handle.
    def force_value *args
      args[3] = VpiForceFlag
      put_value(*args)
    end

    # Releases a previously forced value on this handle.
    def release_value
      # this doesn't really change the value, it only removes the force flag
      put_value(0, VpiIntVal, nil, VpiReleaseFlag)
    end

    # Tests if there is currently a value forced onto this handle.
    def value_forced?
      self[VpiDriver].any? {|d| d.vpiType == VpiForce}
    end


    #---------------------------------------------------------------------------
    # accessing related handles / traversing the hierarchy
    #---------------------------------------------------------------------------

    # Returns an array of child handles of the
    # given types (name or integer constant).
    def [] *aTypes
      handles = []

      aTypes.each do |arg|
        t = resolve_prop_type(arg)

        if itr = vpi_iterate(t, self)
          while h = vpi_scan(itr)
            handles << h
          end
        end
      end

      handles
    end

    # inherit Enumerable methods, such as #each, #map, #select, etc.
    Enumerable.instance_methods.push('each').each do |meth|
      # using a string because define_method
      # does not accept a block until Ruby 1.9
      class_eval %{
        def #{meth}(*args, &block)
          if ary = self[*args]
            ary.#{meth}(&block)
          end
        end
      }, __FILE__, __LINE__
    end

    # bypass Enumerable's #to_a method, which relies on #each
    alias to_a []

    # Sort by absolute VPI path.
    def <=> other
      get_value(VpiFullName) <=> other.get_value(VpiFullName)
    end


    # Inspects the given VPI property names, in
    # addition to those common to all handles.
    def inspect *aPropNames
      aPropNames.unshift :name, :fullName, :size, :file, :lineNo, :hexStrVal

      aPropNames.map! do |name|
        "#{name}=#{__send__(name.to_sym).inspect}"
      end

      "#<Vpi::Handle #{vpiType_s} #{aPropNames.join(', ')}>"
    end

    alias to_s inspect

    # Registers a callback that is invoked
    # whenever the value of this object changes.
    def cbValueChange aOptions = {}, &aHandler
      raise ArgumentError unless block_given?

      aOptions[:time]  ||= S_vpi_time.new(:type => VpiSuppressTime)
      aOptions[:value] ||= S_vpi_value.new(:format => VpiSuppressVal)

      alarm = S_cb_data.new(
        :reason => CbValueChange,
        :obj    => self,
        :time   => aOptions[:time],
        :value  => aOptions[:value],
        :index  => 0
      )

      vpi_register_cb alarm, &aHandler
    end


    #---------------------------------------------------------------------------
    # accessing VPI properties
    #---------------------------------------------------------------------------

    @@propCache = Hash.new {|h, k| h[k] = Property.new(k)}

    # Provides access to this handle's (1) child handles
    # and (2) VPI properties through method calls.  In the
    # case that a child handle has the same name as a VPI
    # property, the child handle will be accessed instead
    # of the VPI property.  However, you can still access
    # the VPI property via #get_value and #put_value.
    def method_missing aMeth, *aArgs, &aBlockArg
      # cache the result for future accesses, in order
      # to cut down number of calls to method_missing()
      eigen_class = (class << self; self; end)

      if child = vpi_handle_by_name(aMeth.to_s, self)
        eigen_class.class_eval do
          define_method aMeth do
            child
          end
        end

        child
      else
        # XXX: using a string because define_method() does
        #      not support a block argument until Ruby 1.9
        eigen_class.class_eval %{
          def #{aMeth}(*a, &b)
            @@propCache[#{aMeth.inspect}].execute(self, *a, &b)
          end
        }, __FILE__, __LINE__

        __send__(aMeth, *aArgs, &aBlockArg)
      end
    end

    private

    class Property # :nodoc:
      def initialize aMethName
        @methName = aMethName.to_s

        # parse property information from the given method name
          tokens = @methName.split('_')

          tokens.last.sub!(/[\?!=]$/, '')
          addendum  = $&
          @isAssign = $& == '='
          isQuery   = $& == '?'

          tokens.last =~ /^[a-z]$/ && tokens.pop
          @accessor = $&

          @name = tokens.pop

          @operation = unless tokens.empty?
            tokens.join('_') << (addendum || '')
          end

        # determine the VPI integer type for the property
          @name = @name.to_ruby_const_name
          @name.insert 0, 'Vpi' unless @name =~ /^[Vv]pi/

          begin
            @type = Vpi.const_get(@name)
          rescue NameError
            raise ArgumentError, "#{@name.inspect} is not a valid VPI property"
          end

        @accessor = if @accessor
          @accessor.to_sym
        else
          # infer accessor from VPI property @name
          if isQuery
            :b
          else
            case @name
            when /Time$/
              :d

            when /Val$/
              :l

            when /Type$/, /Direction$/, /Index$/, /Size$/, /Strength\d?$/, /Polarity$/, /Edge$/, /Offset$/, /Mode$/, /LineNo$/
              :i

            when /Is[A-Z]/, /ed$/
              :b

            when /Name$/, /File$/, /Decompile$/
              :s

            when /Parent$/, /Inst$/, /Range$/, /Driver$/, /Net$/, /Load$/, /Conn$/, /Bit$/, /Word$/, /[LR]hs$/, /(In|Out)$/, /Term$/, /Argument$/, /Condition$/, /Use$/, /Operand$/, /Stmt$/, /Expr$/, /Scope$/, /Memory$/, /Delay$/
              :h
            end
          end
        end
      end

      def execute aHandle, *aArgs, &aBlockArg
        if @operation
          aHandle.__send__(@operation, @type, *aArgs, &aBlockArg)
        else
          case @accessor
          when :d # delay values
            raise NotImplementedError, 'processing of delay values is not yet implemented.'
            # TODO: vpi_put_delays
            # TODO: vpi_get_delays

          when :l # logic values
            if @isAssign
              value = aArgs.shift
              aHandle.put_value(value, @type, *aArgs)
            else
              aHandle.get_value(@type)
            end

          when :i # integer values
            if @isAssign
              raise NotImplementedError
            else
              vpi_get(@type, aHandle)
            end

          when :b # boolean values
            if @isAssign
              raise NotImplementedError
            else
              value = vpi_get(@type, aHandle)
              value && (value != 0)	# zero is false in C
            end

          when :s # string values
            if @isAssign
              raise NotImplementedError
            else
              vpi_get_str(@type, aHandle)
            end

          when :h # handle values
            if @isAssign
              raise NotImplementedError
            else
              vpi_handle(@type, aHandle)
            end

          when :a # array of child handles
            if @isAssign
              raise NotImplementedError
            else
              aHandle[@type]
            end

          else
            raise NoMethodError, "cannot access VPI property #{@name.inspect} for handle #{aHandle.inspect} through method #{@methName.inspect} with arguments #{aArgs.inspect}"
          end
        end
      end
    end

    # resolve type names into type constants
    def resolve_prop_type aNameOrType
      if aNameOrType.respond_to? :to_int
        aNameOrType.to_int
      else
        @@propCache[aNameOrType.to_sym].type
      end
    end
  end

  #-----------------------------------------------------------------------------
  # value change / edge detection
  #-----------------------------------------------------------------------------

  @@edgeHandles = []
  @@edgeHandles_lock = Mutex.new

  class << @@edgeHandles
    # Begins monitoring the given handle for value change.
    def monitor aHandle
      # ignore handles that cannot hold a meaningful value
      type = aHandle.type_s
      return unless type =~ /Reg|Net|Word/ and type !~ /Bit/

      @@edgeHandles_lock.synchronize do
        unless include? aHandle
          aHandle.__edge__update_previous_value
        end
      end
    end

    # Refreshes the cached value of all monitored handles.
    def update
      @@edgeHandles_lock.synchronize do
        each do |handle|
          handle.__edge__update_previous_value
        end
      end
    end
  end

  %w[
    vpi_handle_by_name
    vpi_handle_by_index
    vpi_handle
    vpi_scan
  ].each do |src|
    dst = "__value_change__#{src}"
    alias_method dst, src

    define_method src do |*args|
      if result = __send__(dst, *args)
        @@edgeHandles.monitor(result)
      end

      result
    end
  end


  ##############################################################################
  # callbacks
  ##############################################################################

  Callback = Struct.new :handler, :token #:nodoc:
  @@callbacks = {}

  alias __callback__vpi_register_cb vpi_register_cb

  # This is a Ruby version of the vpi_register_cb C function.  It is
  # identical to the C function, except for the following differences:
  #
  # * This method accepts a block (callback handler)
  #   which is executed whenever the callback occurs.
  #
  # * This method overwrites the +cb_rtn+ and +user_data+
  #   fields of the given +S_cb_data+ object.
  #
  def vpi_register_cb aData, &aHandler # :yields: Vpi::S_cb_data
    raise ArgumentError, "block must be given" unless block_given?

    key = aHandler.object_id.to_s

    # register the callback with Verilog
    aData.user_data = key
    aData.cb_rtn    = Vlog_relay_ruby
    token           = __callback__vpi_register_cb(aData)

    @@callbacks[key]  = Callback.new(aHandler, token)
    token
  end

  alias __callback__vpi_remove_cb vpi_remove_cb

  def vpi_remove_cb aData # :nodoc:
    key = aData.user_data

    if c = @@callbacks[key]
      __callback__vpi_remove_cb c.token
      @@callbacks.delete key
    end
  end


  ##############################################################################
  # simulation control
  ##############################################################################

  # Transfers control to the simulator, which will return control
  # during the given time slot after the given number of time steps.
  def __control__relay_verilog aTimeSlot, aNumSteps #:nodoc:
    # schedule wake-up callback from verilog
    time            = S_vpi_time.new
    time.integer    = aNumSteps
    time.type       = VpiSimTime

    value           = S_vpi_value.new
    value.format    = VpiSuppressVal

    alarm           = S_cb_data.new
    alarm.reason    = aTimeSlot
    alarm.cb_rtn    = Vlog_relay_ruby
    alarm.obj       = nil
    alarm.time      = time
    alarm.value     = value
    alarm.index     = 0
    alarm.user_data = nil

    vpi_free_object(__callback__vpi_register_cb(alarm))


    # transfer control to verilog
    loop do
      __extension__relay_verilog

      if reason = __extension__relay_ruby_reason # might be nil
        dst = reason.user_data

        if c = @@callbacks[dst]
          c.handler.call reason
        else
          # TODO: make sure this works with the thread scheduler
          break # main thread is receiver
        end
      end
    end
  end


  ##############################################################################
  # utility
  ##############################################################################

  # Returns the current simulation time as an integer.
  def simulation_time
    @@time
  end

  class S_vpi_time
    # Returns the high and low portions of
    # this time as a single 64-bit integer.
    def integer
      (self.high << INTEGER_BITS) | self.low
    end

    # Sets the high and low portions of this
    # time from the given 64-bit integer.
    def integer= aValue
      self.low  = aValue & INTEGER_MASK
      self.high = (aValue >> INTEGER_BITS) & INTEGER_MASK
    end

    alias to_i integer
    alias to_f real
  end

  class S_vpi_value
    # Returns the value in the given format.
    def read aFormat
      case aFormat
      when VpiBinStrVal, VpiOctStrVal, VpiDecStrVal, VpiHexStrVal, VpiStringVal
        value.str.to_s

      when VpiScalarVal
        value.scalar.to_i

      when VpiIntVal
        value.integer.to_i

      when VpiRealVal
        value.real.to_f

      when VpiTimeVal
        value.time

      when VpiVectorVal
        value.vector

      when VpiStrengthVal
        value.strength

      else
        raise "unknown format: #{aFormat.inspect}"
      end
    end

    alias [] read
  end

  # make VPI structs more accessible by allowing their
  # members to be initialized through the constructor
  constants.grep(/^S_/).each do |s|
    const_get(s).class_eval do
      alias __struct__initialize initialize

      def initialize aMembers = {} #:nodoc:
        __struct__initialize

        aMembers.each_pair do |k, v|
          __send__ "#{k}=", v
        end
      end
    end
  end


  ##############################################################################
  # concurrent processes
  # see http://rubyforge.org/pipermail/ruby-vpi-discuss/2007-August/000046.html
  ##############################################################################

  Thread.abort_on_exception = true

  @@thread2state      = { Thread.main => :run }
  @@thread2state_lock = Mutex.new

  @@scheduler = Thread.new do
    @@time = 0
    __control__relay_verilog CbReadOnlySynch, 0 unless USE_PROTOTYPE

    # pause because boot loader is not fully init yet
    Thread.stop

    loop do
      # finish software execution in current time step
      loop do
        ready = @@thread2state_lock.synchronize do
          Thread.exit if @@thread2state.empty?

          @@thread2state.all? do |(thread, state)|
            thread.stop? and state == :wait
          end
        end

        if ready
          break
        else
          Thread.pass
        end
      end

      @@edgeHandles.update

      __control__relay_verilog CbAfterDelay, 1 unless USE_PROTOTYPE
      __scheduler__flush_writes


      # run hardware in next time step
      @@time += 1

      if USE_PROTOTYPE
        __proto__simulate_hardware
        __scheduler__flush_writes
      else
        __control__relay_verilog CbReadOnlySynch, 0
      end


      # resume software execution in new time step
      @@thread2state_lock.synchronize do
        @@thread2state.keys.each do |thr|
          @@thread2state[thr] = :run
          thr.wakeup
        end
      end
    end
  end

  def __scheduler__start #:nodoc:
    @@scheduler.wakeup
  end

  def __scheduler__ensure_caller_is_registered *args #:nodoc:
    isRegistered = @@thread2state_lock.synchronize do
      @@thread2state.key? Thread.current
    end

    unless isRegistered
      raise SecurityError, *args
    end
  end

  # Creates a new concurrent thread, which will execute the
  # given block with the given arguments, and returns it.
  def process *aBlockArgs
    __scheduler__ensure_caller_is_registered 'a process can only be spawned by another process'
    raise ArgumentError, "block must be given" unless block_given?

    Thread.new do
      # register with scheduler
      @@thread2state_lock.synchronize do
        @@thread2state[Thread.current] = :run
      end

      yield(*aBlockArgs)

      # unregister before exiting
      @@thread2state_lock.synchronize do
        @@thread2state.delete Thread.current
      end
    end
  end

  # Wraps the given block inside an infinite loop and executes
  # it inside a new concurrent thread (see Vpi::process).
  def always *aBlockArgs, &aBlock
    process do
      loop do
        aBlock.call(*aBlockArgs)
      end
    end
  end

  alias forever always

  # Wait for the given number of time steps.
  def wait aNumTimeSteps = 1
    __scheduler__ensure_caller_is_registered 'this method can only be invoked from within a process'

    aNumTimeSteps.times do
      @@thread2state_lock.synchronize do
        @@thread2state[Thread.current] = :wait
      end

      # NOTE: scheduler will set state to :run before waking up this thread
      Thread.stop
    end
  end

  alias advance_time wait

  # End the simulation.
  def finish
    __scheduler__ensure_caller_is_registered 'this method can only be invoked from within a process'

    @@scheduler.exit
  end


  #-----------------------------------------------------------------------------
  # buffer/cache all writes
  #-----------------------------------------------------------------------------

  @@handle2write      = Hash.new {|h,k| h[k] = []}
  @@handle2write_lock = Mutex.new

  alias __scheduler__vpi_put_value vpi_put_value

  def vpi_put_value aHandle, *aArgs #:nodoc:
    @@handle2write_lock.synchronize do
      @@handle2write[aHandle] << aArgs
    end
  end

  def __scheduler__flush_writes #:nodoc:
    @@handle2write_lock.synchronize do
      @@handle2write.each_pair do |handle, writes|
        writes.each do |args|
          __scheduler__vpi_put_value(handle, *args)
        end

        writes.clear
      end
    end
  end


  #-----------------------------------------------------------------------------
  # boot loader stuff
  #-----------------------------------------------------------------------------

  # Finalizes the simulation for the boot loader.
  def __boot__finalize #:nodoc:
    raise unless Thread.current == Thread.main
    __scheduler__ensure_caller_is_registered

    # let the thread scheduler take over when the main thread is finished
    @@thread2state_lock.synchronize do
      @@thread2state.delete Thread.main
    end

    @@scheduler.wakeup if @@scheduler.alive?
    raise unless @@scheduler.join

    # return control to the simulator before Ruby exits.
    # otherwise, the simulator will not have a chance to do
    # any clean up or finish any pending tasks that remain
    __extension__relay_verilog unless $!
  end
end
