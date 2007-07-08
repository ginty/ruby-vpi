# A library for parsing Verilog source code.
#--
# Copyright 2006-2007 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'ruby-vpi/util'

class VerilogParser
  attr_reader :modules, :constants, :includes

  # Parses the given Verilog source code.
  def initialize aInput
    input = aInput.dup

    # strip comments
      input.gsub! %r{//.*$}, ''
      input.gsub! %r{/\*.*?\*/}m, ''

    @modules = input.scan(%r{module.*?;}m).map! do |decl|
      Module.new decl
    end

    @constants = input.scan(%r{(`define\s+(\w+)\s+(.+))}).map! do |matches|
      Constant.new(*matches)
    end

    @includes = input.scan(%r{(`include\s*(\S+))}).map! do |matches|
      Include.new(*matches)
    end
  end

  Constant = Struct.new(:decl, :name, :value)
  Include = Struct.new(:decl, :target)

  class Module
    attr_reader :decl, :name, :parameters, :ports

    def initialize aDecl
      @decl = aDecl.strip

      @decl =~ %r{module\s+(\w+)\s*(?:\#\((.*?)\))?\s*\((.*?)\)\s*;}m
      @name, paramDecls, portDecls = $1, $2, $3

      @parameters =
        if paramDecls =~ %r{\bparameter\b(.*)$}
          $1.split(',').map! do |decl|
            Parameter.new decl
          end
        else
          []
        end

      @ports = portDecls.split(',').map! do |decl|
        Port.new decl
      end
    end

    class Parameter
      attr_reader :decl, :name, :value

      def initialize aDecl
        @decl = aDecl.strip
        @name, @value = @decl.split('=').map! {|s| s.strip}
      end
    end

    class Port
      attr_reader :decl, :name, :size

      def initialize aDecl
        @decl = aDecl.strip

        @decl =~ /(\[.*?\])?\s*(\w+)$/
        @size, @name = $1, $2
      end

      def input?
        @decl =~ /\binput\b/
      end

      def output?
        @decl =~ /\boutput\b/
      end

      def reg?
        @decl =~ /\breg\b/
      end
    end
  end
end

class String
  # Converts this string containing Verilog code into syntactically correct Ruby
  # code.
  def verilog_to_ruby
    content = self.dup

    # single-line comments
      content.gsub! %r{//(.*)$}, '#\1'

    # multi-line comments
      content.gsub! %r{/\*.*?\*/}m, "\n=begin\n\\0\n=end\n"

    # preprocessor directives
      content.gsub! %r{`include}, '#\0'

      content.gsub! %r{`define\s+(\w+)\s+(.+)} do
        "#{$1.to_ruby_const_name} = #{$2}"
      end

      content.gsub! %r{`+}, ''

    # numbers
      content.gsub! %r{\d*\'([dohb]\w+)}, '0\1'

    # ranges
      content.gsub! %r{(\S)\s*:\s*(\S)}, '\1..\2'

    content
  end
end
