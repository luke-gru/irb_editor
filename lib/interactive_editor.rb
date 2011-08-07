# vim: set syntax=ruby :
# Giles Bowkett, Greg Brown, and several audience members from Giles' Ruby East presentation.
# http://gilesbowkett.blogspot.com/2007/10/use-vi-or-any-text-editor-from-within.html
#
# modified for personal use by Luke Gruber

require 'irb'
require 'fileutils'
require 'tempfile'
require 'shellwords'
require 'yaml'

class InteractiveEditor
  VERSION = '0.0.8'

  attr_accessor :editor

  def initialize(editor)
    @editor = editor.to_s
  end

  def edit(object, file=nil, copy=:nocopy)
    object = object == TOPLEVEL_BINDING.eval('self') ? nil : object
    # instead of always going back to the same file, pass the symbol :new to get
    # a new Tempfile again
    if file && file.respond_to?(:scan)
      file = File.expand_path(file)
      @symfile = false
    else
      @symfile = true
    end

    copy == :nocopy ? @copy = false : @copy = true

    if @symfile
      case file
      when :new
        @file = nil
      end
    end

    if @copy
      @orig = File.expand_path(file)
      @file = nil
    end

    current_file = if file && !@symfile && !@copy
      FileUtils.touch(file) unless File.exist?(file)
      File.new(file)
    else
      if @file && File.exist?(@file.path) && !object
        @file
      else
        Tempfile.new( object ? ["yobj_tempfile", ".yml"] : ["irb_tempfile", ".rb"] )
      end
    end

    if object
      File.open( current_file.path, 'w' ) { |f| f << object.to_yaml }
    else
      @file = current_file
      mtime = File.stat(@file.path).mtime
    end

    if @copy
      File.open(@orig, "r+") do |outf|
        File.open(@file, "w+") do |inf|
          inf << outf.read
        end
      end
    end

    args = Shellwords.shellwords(@editor) #parse @editor as arguments could be complex
    args << current_file.path
    current_file.close rescue nil
    Exec.system(*args)

    if object
      File.exists?(current_file.path) ? YAML.load_file(current_file.path) : object
    elsif mtime < File.stat(@file.path).mtime
      execute
    end
  end

  def execute
    eval(IO.read(@file.path), TOPLEVEL_BINDING)
  end

  def self.edit(editor, self_, file=nil, copy=:nocopy)
    #maybe serialise last file to disk, for recovery
    (IRB.conf[:interactive_editors] ||=
      Hash.new { |h,k| h[k] = InteractiveEditor.new(k) })[editor].edit(self_, file, copy)
  end

  module Exec
    module Java
      def system(file, *args)
        require 'spoon'
        Process.waitpid(Spoon.spawnp(file, *args))
      rescue Errno::ECHILD => e
        raise "error exec'ing #{file}: #{e}"
      end
    end

    module MRI
      def system(file, *args)
        Kernel::system(file, *args) #or raise "error exec'ing #{file}: #{$?}"
      end
    end

    extend RUBY_PLATFORM =~ /java/ ? Java : MRI
  end

  module Editors
    {
      :vi    => nil,
      :vim   => nil,
      :emacs => nil,
      :nano  => nil,
      :mate  => 'mate -w',
      :mvim  => 'mvim -g -f' + case ENV['TERM_PROGRAM']
        when 'iTerm.app';      ' -c "au VimLeave * !open -a iTerm"'
        when 'Apple_Terminal'; ' -c "au VimLeave * !open -a Terminal"'
        else '' #don't do tricky things if we don't know the Term
      end
    }.each do |k,v|
      if ENV["EDITOR"] =~ /#{k}/ #modified, LG
        define_method(k) do |*args|
        InteractiveEditor.edit(v || k, self, *args)
        end
      @found = true
      elsif !@found
        define_method(k) do |*args|
          InteractiveEditor.edit(v || k, self, *args)
        end
      end
    end

    def ed(*args)
      if ENV['EDITOR'].to_s.size > 0
        InteractiveEditor.edit(ENV['EDITOR'], self, *args)
      else
        raise "You need to set the EDITOR environment variable first"
      end
    end
  end
end

include InteractiveEditor::Editors
