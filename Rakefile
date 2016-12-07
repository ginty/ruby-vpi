# = Environment variables
#
# CFLAGS        :: Override the default options passed to the compiler.
# CFLAGS_EXTRA  :: Provide additional options for the compiler.
# LDFLAGS       :: Override the default options passed to the linker.
# LDFLAGS_EXTRA :: Provide additional options for the linker.
#
#--
# Copyright 2006 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'rake/clean'

require 'tempfile'
require 'rbconfig'

PROJECT_LIBS = File.join(File.dirname(__FILE__), 'lib')
DYNAMIC_DOCS = 'ruby-vpi-dynamic.rb'

$:.unshift PROJECT_LIBS
require 'ruby-vpi'
require 'ruby-vpi/rake'
require 'ruby-vpi/util'

task :default => :build

# utility

  # Returns a temporary, unique path ready for
  # use. No file exists at the returned path.
  def generate_temp_path
    path = Tempfile.new($$).path
    rm_f path
    path
  end

  # propogate cleaning tasks recursively to lower levels
  %w[clean clobber].each do |t|
    task t do
      files = FileList['**/Rakefile'].exclude('_darcs') - %w[Rakefile]

      # allows propogation to lower levels when gem not installed
      ENV['RUBYLIB'] = PROJECT_LIBS

      files.each do |f|
        cd File.dirname(f) do
          sh 'rake', t
        end
      end
    end
  end

# extension
  desc "Builds object files for all simulators."
  task :build

  directory 'obj'
  CLOBBER.include 'obj'

  ccFlags = ENV['CFLAGS_EXTRA']
  ldFlags = ENV['LDFLAGS_EXTRA']

  RubyVPI::SIMULATORS.each do |sim|
    taskName = "build_#{sim.id}"

    desc "Builds object files for #{sim.name}."
    task taskName => ['obj', 'ext'] do
      src = RubyVPI::Project[:name] + '.' + Config::CONFIG['DLEXT']
      dst = File.expand_path(File.join('obj', "#{sim.id}.so"))

      unless File.exist? dst
        cd 'ext' do
          ENV['CFLAGS_EXTRA']  = [ccFlags, sim.compiler_args].compact.join(' ')
          ENV['LDFLAGS_EXTRA'] = [ldFlags, sim.linker_args].compact.join(' ')

          sh "rake SIMULATOR=#{sim.id}"
          mv src, dst
          sh 'rake clean'
        end
      end
    end

    task :build => taskName
  end

# documentation
  desc "Build the documentation."
  task :doc => 'doc/guide'

  desc 'Generate the HTML user guide.'
  task 'doc/guide' => 'doc/guide.html'

  file 'doc/guide.html' => 'doc/guide.erb' do |t|
    begin
      sh "gerbil -u html #{t.prerequisites} > #{t.name}"
    rescue
      rm_f t.name
      raise
    end
  end
  CLOBBER.include 'doc/guide.html'

# API reference
  directory 'doc/api'
  CLOBBER.include 'doc/api'

  desc "Build API reference."
  task :ref => ['doc/api/ruby', 'doc/api/c']

  file DYNAMIC_DOCS => 'ext/vpi_user.h' do |t|
    File.open t.name, 'w' do |f|
      f.puts "# This module encapsulates all functionality provided by the C-language Application Programming Interface (API) of the Verilog Procedural Interface (VPI).  See the ext/vpi_user.h file for details."
      f.puts "module VPI"
        body = File.read(t.prerequisites[0])

        # constants
        body.scan %r{^#define\s+(vpi\S+)\s+(\S+)\s+/\*+(.*?)\*+/} do |var, val, info|
          const = var.to_ruby_const_name
          f.puts '# ' << info
          f.puts "#{const}=#{val}"

          f.puts "# Returns the #{const} constant: #{info}"
          f.puts "def self.#{var}; end"
        end

        # functions
        body.scan %r{^XXTERN\s+(\S+\s+\*?)(\S+)\s+PROTO_PARAMS\(\((.*?)\)\);}m do |type, func, args|
          meth = func.gsub(/\W/, '')
          args = args.gsub(/[\r\n]/, ' ')

          [
            [ /PLI_BYTE8(\s*)\*(\s*data)/ , 'Object\1\2'  ],
            [ /PLI_BYTE8(\s*)\*?/         , 'String\1'    ],
            [ /PLI_U?INT32(\s*)\*/        , 'Array\1'     ],
            [ /PLI_U?INT32/               , 'Integer'     ],
            [ /\b[ps]_/                   , 'VPI::S_'     ],
            [ 'vpiHandle'                 , 'VPI::Handle' ],
            [ /va_list\s+\w+/             , '...'         ],
            [ /\bvoid(\s*)\*/             , 'Object\1'    ],
            [ 'void'                      , 'nil'         ],
          ].each do |(a, b)|
            args.gsub! a, b
            type.gsub! a, b
          end

          f.puts "# #{func}(#{args}) returns #{type}"
          f.puts "def self.#{meth}; end"
        end

        # VPI::Handle methods
        f.puts "class Handle"
          require 'lib/ruby-vpi/core/edge-methods.rb'
          RubyVPI::EdgeClass::DETECTION_METHODS.each do |m|
            f.puts "# #{m.info}"
            f.puts "def #{m.name}; end"
          end
        f.puts "end"
      f.puts "end"
    end
  end
  CLOBBER.include DYNAMIC_DOCS

  desc 'Build API reference for C.'
  file 'doc/api/c' => 'doc/api' do |t|
    # doxygen outputs to this temporary destination
    tempDest = 'ext/html'

    cd File.dirname(tempDest) do
      sh "doxygen"
    end

    mv tempDest, t.name
  end

# utility
  desc "Ensure that examples work with $SIMULATOR"
  task :test => :build do
    # ensures that current sources are tested instead of the installed gem
    ENV['RUBYLIB'] = PROJECT_LIBS

    sim = ENV['SIMULATOR'] || 'cver'

    FileList['examples/**/*.rake'].each do |runner|
      sh 'rake', '-f', runner, sim
    end
  end
