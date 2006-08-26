#!/usr/bin/ruby -w
#
# == Synopsis
# Generates Ruby-VPI tests from Verilog 2001 module declarations. A generated test is composed of the following parts.
#
# Runner:: Written in Rake, this file builds and runs the test bench.
#
# Bench:: Written in Verilog and Ruby, these files define the testing environment.
#
# Design:: Written in Ruby, this file provides an interface to the Verilog module under test.
#
# Prototype:: Written in Ruby, this file defines a prototype of the design under test.
#
# Specification:: Written in Ruby, this file verifies the design.
#
# The reason for dividing a single test into these parts is mainly to decouple the design from the specification. This allows humans to focus on writing the specification while the remainder is automatically generated by this tool.
#
# For example, when the interface of a Verilog module changes, you would simply re-run this tool to incorporate those changes into the test without diverting your focus from the specification.
#
# == Usage
# ruby generate_test.rb [option...] [input-file...]
#
# option::
# 	Specify "--help" to see a list of options.
#
# input-file::
# 	A source file which contains one or more Verilog 2001 module declarations.
#
# * If no input files are specified, then the standard input stream will be read instead.
# * The first signal parameter in a module's declaration is assumed to be the clocking signal.
# * Existing output files will be backed-up before being over-written. A backed-up file has a tilde (~) appended to its name.

=begin
  Copyright 2006 Suraj N. Kurapati

  This file is part of Ruby-VPI.

  Ruby-VPI is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.

  Ruby-VPI is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Ruby-VPI; if not, write to the Free Software Foundation,
  Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
=end

require 'fileutils'


# Writes the given contents to the file at the given path. If the given path already exists, then a backup is created before proceeding.
def write_file aPath, aContent
  # create a backup
  if File.exist? aPath
    backupPath = aPath.dup

    while File.exist? backupPath
      backupPath << '~'
    end

    FileUtils.cp aPath, backupPath, :preserve => true
  end


  # write the file
  File.open(aPath, 'w') {|f| f << aContent}
end

# Returns a comma-separated string of parameter declarations in Verilog module instantiation format.
def make_inst_param_decl(paramNames)
  paramNames.inject([]) {|acc, param| acc << ".#{param}(#{param})"}.join(', ')
end

# Generates and returns the content of the Verilog bench file, which cooperates with the Ruby bench file to run the test bench.
def generate_verilog_bench aModuleInfo, aOutputInfo

  # configuration parameters for design under test
  configDecl = aModuleInfo.paramDecls.inject('') do |acc, decl|
    acc << "parameter #{decl};\n"
  end


  # accessors for design under test interface
  portInitDecl = aModuleInfo.portDecls.inject('') do |acc, decl|
    { 'input' => 'reg', 'output' => 'wire' }.each_pair do |key, val|
      decl.sub! %r{\b#{key}\b(.*?)$}, "#{val}\\1;"
    end

    decl.strip!
    acc << decl << "\n"
  end


  # instantiation for the design under test
  instConfigDecl = make_inst_param_decl(aModuleInfo.paramNames)
  instParamDecl = make_inst_param_decl(aModuleInfo.portNames)

  instDecl = "#{aModuleInfo.name} " << (
    unless instConfigDecl.empty?
      '#(' << instConfigDecl << ')'
    else
      ''
    end
  ) << " #{aOutputInfo.verilogBenchName}#{aOutputInfo.designSuffix} (#{instParamDecl});"


  clockSignal = aModuleInfo.portNames.first

  %{
    module #{aOutputInfo.verilogBenchName};

      // configuration for the design under test
      #{configDecl}

      // accessors for the design under test
      #{portInitDecl}

      // instantiate the design under test
      #{instDecl}

      // interface to Ruby-VPI
      initial begin
        #{clockSignal} = 0;
        $ruby_init("ruby", "-w", "#{aOutputInfo.rubyBenchPath}"#{%{, "-f", "s"} if aOutputInfo.specFormat == :RSpec});
      end

      // generate a 50% duty-cycle clock for the design under test
      always begin
        #5 #{clockSignal} = ~#{clockSignal};
      end

      // transfer control to Ruby-VPI every clock cycle
      always @(posedge #{clockSignal}) begin
        #1 $ruby_relay();
      end

    endmodule
  }
end

# Generates and returns the content of the Ruby bench file, which cooperates with the Verilog bench file to run the test bench.
def generate_ruby_bench aModuleInfo, aOutputInfo
  %{
    #{
      case aOutputInfo.specFormat
        when :UnitTest
          "require 'test/unit'"

        when :RSpec
          "require 'rspec'"
      end
    }

    # initalize the bench
    require 'bench'
    setup_bench '#{aModuleInfo.name + aOutputInfo.suffix}', :#{aOutputInfo.protoClassName}

    # service the $ruby_relay() callback
    #{
      case aOutputInfo.specFormat
        when :UnitTest, :RSpec
          "# ... #{aOutputInfo.specFormat} will take control from here."

        else
          aOutputInfo.specClassName + '.new'
      end
    }
  }
end

# Generates and returns the content of the Ruby design file, which is a Ruby abstraction of the Verilog module's interface.
def generate_design aModuleInfo, aOutputInfo
  accessorDecl = aModuleInfo.portNames.inject([]) do |acc, port|
    acc << ":#{port}"
  end.join(', ')

  portInitDecl = aModuleInfo.portNames.inject('') do |acc, port|
    acc << %{@#{port} = vpi_handle_by_name("#{aOutputInfo.verilogBenchName}.#{port}", nil)\n}
  end


  # make module parameters as class constants
  paramInitDecl = aModuleInfo.paramDecls.inject('') do |acc, decl|
    acc << decl.strip.capitalize
  end

  portResetCode = aModuleInfo.inputPortNames[1..-1].inject('') do |acc, port|
    acc << %{@#{port}.hexStrVal = 'x'\n}
  end

  %{
    # An interface to the design under test.
    class #{aOutputInfo.designClassName}
      include Vpi

      #{paramInitDecl}
      attr_reader #{accessorDecl}

      def initialize
        #{portInitDecl}
      end

      def reset!
        #{portResetCode}
      end
    end
  }
end

# Generates and returns the content of the Ruby prototype file, which is a Ruby prototype of the design under test.
def generate_proto aModuleInfo, aOutputInfo
  %{
    # A prototype of the design under test.
    class #{aOutputInfo.protoClassName} < #{aOutputInfo.designClassName}
      def simulate!
        # read inputs
        # simulate design's behavior
        # produce outputs
      end
    end
  }
end

# Generates and returns the content of the Ruby specification file, which verifies the design under test.
def generate_spec aModuleInfo, aOutputInfo
  accessorTestDecl = aModuleInfo.portNames.inject('') do |acc, param|
    acc << "def test_#{param}\nend\n\n"
  end

  %{# A specification which verifies the design under test.
    #{
      case aOutputInfo.specFormat
        when :UnitTest
          %{
            class #{aOutputInfo.specClassName} < Test::Unit::TestCase
              include Vpi

              def setup
                @design = #{aOutputInfo.designClassName}.new
              end

              #{accessorTestDecl}
            end
          }

        when :RSpec
          %{
            include Vpi

            context "A new #{aOutputInfo.designClassName}" do
              setup do
                @design = #{aOutputInfo.designClassName}.new
                @design.reset!
              end

              specify "should ..." do
                # @design.should ...
              end
            end
          }

        else
          %{
            class #{aOutputInfo.specClassName}
              include Vpi

              def initialize
                @design = #{aOutputInfo.designClassName}.new
              end
            end
          }
      end
    }
  }
end

# Generates and returns the content of the runner, which builds and runs the entire test bench.
def generate_runner aModuleInfo, aOutputInfo
  %{
    RUBY_VPI_PATH = '#{aOutputInfo.rubyVpiPath}'

    SIMULATOR_SOURCES = [
      '#{aOutputInfo.verilogBenchPath}',
      '#{aModuleInfo.name}.v',
    ]

    SIMULATOR_TARGET = '#{aOutputInfo.verilogBenchName}'

    # command-line arguments for the simulator
    SIMULATOR_ARGS = {
      :cver => '',
      :ivl => '',
      :vcs => '',
      :vsim => '',
    }

    load "\#{RUBY_VPI_PATH}#{OutputInfo::RUNNER_TMPL_REL_PATH}"
  }
end

# Holds information about a parsed Verilog module.
class ModuleInfo
  attr_reader :name, :portNames, :paramNames, :portDecls, :paramDecls, :inputPortNames

  def initialize aDecl
    aDecl =~ %r{module\s+(\w+)\s*(\#\((.*?)\))?\s*\((.*?)\)\s*;}
    @name, paramDecl, portDecl = $1, $3 || '', $4


    # parse configuration parameters
    paramDecl.gsub! %r{\bparameter\b}, ''
    paramDecl.strip!

    @paramDecls = paramDecl.split(/,/)

    @paramNames = paramDecls.inject([]) do |acc, decl|
      acc << decl.scan(%r{\w+}).first
    end


    # parse signal parameters
    portDecl.gsub! %r{\breg\b}, ''
    portDecl.strip!

    @portDecls = portDecl.split(/,/)

    @inputPortNames = []

    @portNames = portDecls.inject([]) do |acc, decl|
      name = decl.scan(%r{\w+}).last
      @inputPortNames << name if decl =~ /\binput\b/

      acc << name
    end
  end
end

# Holds information about the output destinations of a parsed Verilog module.
class OutputInfo
  RUBY_EXT = '.rb'
  VERILOG_EXT = '.v'
  RUNNER_EXT = '.rake'

  RUNNER_TMPL_REL_PATH = '/tpl/runner.rake'

  SPEC_FORMATS = [:RSpec, :UnitTest, :Generic]

  attr_reader :verilogBenchName, :verilogBenchPath, :rubyBenchName, :rubyBenchPath, :designName, :designClassName, :designPath, :specName, :specClassName, :specFormat, :specPath, :rubyVpiPath, :runnerName, :runnerPath, :protoName, :protoPath, :protoClassName

  attr_reader :testName, :suffix, :benchSuffix, :designSuffix, :specSuffix, :runnerSuffix, :protoSuffix

  def initialize aModuleName, aSpecFormat, aTestName, aRubyVpiPath
    raise ArgumentError unless SPEC_FORMATS.include? aSpecFormat
    @specFormat = aSpecFormat
    @testName = aTestName

    @suffix = '_' + @testName
    @benchSuffix = @suffix + '_bench'
    @designSuffix = @suffix + '_design'
    @specSuffix = @suffix + '_spec'
    @runnerSuffix = @suffix + '_runner'
    @protoSuffix = @suffix + '_proto'

    @rubyVpiPath = aRubyVpiPath

    @verilogBenchName = aModuleName + @benchSuffix
    @verilogBenchPath = @verilogBenchName + VERILOG_EXT

    @rubyBenchName = aModuleName + @benchSuffix
    @rubyBenchPath = @rubyBenchName + RUBY_EXT

    @designName = aModuleName + @designSuffix
    @designPath = @designName + RUBY_EXT

    @protoName = aModuleName + @protoSuffix
    @protoPath = @protoName + RUBY_EXT

    @specName = aModuleName + @specSuffix
    @specPath = @specName + RUBY_EXT

    @designClassName = aModuleName.capitalize
    @protoClassName = @designClassName + 'Proto'
    @specClassName = @specName.capitalize

    @runnerName = aModuleName + @runnerSuffix
    @runnerPath = @runnerName + RUNNER_EXT
  end
end

if $0 == __FILE__
  require 'optparse'
  require 'rdoc/usage'

  # parse command-line options
    optSpecFmt = :Generic
    optTestName = 'test'

    optsParser = OptionParser.new
    optsParser.on('-h', '--help', 'show this help message') {raise}
    optsParser.on('-u', '--unit', 'use Test::Unit specification format') {|val| optSpecFmt = :UnitTest if val}
    optsParser.on('-r', '--rspec', 'use RSpec specification format') {|val| optSpecFmt = :RSpec if val}
    optsParser.on('-n', '--name NAME', 'specify name of generated test') {|val| optTestName = val}

    begin
      optsParser.parse!(ARGV)
    rescue
      at_exit {puts optsParser}
      RDoc::usage	# NOTE: this terminates the program
    end

    puts "Using name `#{optTestName}' for generated test."
    puts "Using #{optSpecFmt} specification format."

  # sanitize the input
    input = ARGF.read

    # remove single-line comments
      input.gsub! %r{//.*$}, ''

    # collapse the input into a single line
      input.tr! "\n", ''

    # remove multi-line comments
      input.gsub! %r{/\*.*?\*/}, ''

  # parse the input
    input.scan(%r{module.*?;}).each do |moduleDecl|
      puts

      m = ModuleInfo.new(moduleDecl).freeze
      puts "Parsed module: #{m.name}"

      # generate output
        o = OutputInfo.new(m.name, optSpecFmt, optTestName, File.dirname(File.dirname(__FILE__))).freeze

        write_file o.runnerPath, generate_runner(m, o)
        puts "- Generated runner:           #{o.runnerPath}"

        write_file o.verilogBenchPath, generate_verilog_bench(m, o)
        puts "- Generated bench:            #{o.verilogBenchPath}"

        write_file o.rubyBenchPath, generate_ruby_bench(m, o)
        puts "- Generated bench:            #{o.rubyBenchPath}"

        write_file o.designPath, generate_design(m, o)
        puts "- Generated design:           #{o.designPath}"

        write_file o.protoPath, generate_proto(m, o)
        puts "- Generated prototype:        #{o.protoPath}"

        write_file o.specPath, generate_spec(m, o)
        puts "- Generated specification:    #{o.specPath}"
    end
end
