activesupport_path = File.expand_path('../../../../activesupport/lib', __FILE__)
$:.unshift(activesupport_path) if File.directory?(activesupport_path) && !$:.include?(activesupport_path)

require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/object/metaclass'
require 'active_support/core_ext/array/extract_options'
require 'active_support/core_ext/hash/deep_merge'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/string/inflections'

# TODO: Do not always push on vendored thor
$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/vendor/thor-0.12.3/lib")
require 'rails/generators/base'
require 'rails/generators/named_base'

module Rails
  module Generators
    DEFAULT_ALIASES = {
      :rails => {
        :actions => '-a',
        :orm => '-o',
        :resource_controller => '-c',
        :scaffold_controller => '-c',
        :stylesheets => '-y',
        :template_engine => '-e',
        :test_framework => '-t'
      },

      :test_unit => {
        :fixture_replacement => '-r',
      },

      :plugin => {
        :generator => '-g',
        :tasks => '-r'
      }
    }

    DEFAULT_OPTIONS = {
      :active_record => {
        :migration  => true,
        :timestamps => true
      },

      :erb => {
        :layout => true
      },

      :rails => {
        :force_plural => false,
        :helper => true,
        :layout => true,
        :orm => :active_record,
        :integration_tool => :test_unit,
        :performance_tool => :test_unit,
        :resource_controller => :controller,
        :scaffold_controller => :scaffold_controller,
        :singleton => false,
        :stylesheets => true,
        :template_engine => :erb,
        :test_framework => :test_unit
      },

      :test_unit => {
        :fixture => true,
        :fixture_replacement => nil
      },

      :plugin => {
        :generator => false,
        :tasks => false
      }
    }

    def self.configure!(config = Rails.application.config.generators) #:nodoc:
      no_color! unless config.colorize_logging
      aliases.deep_merge! config.aliases
      options.deep_merge! config.options
    end

    def self.aliases #:nodoc:
      @aliases ||= DEFAULT_ALIASES.dup
    end

    def self.options #:nodoc:
      @options ||= DEFAULT_OPTIONS.dup
    end

    # Hold configured generators fallbacks. If a plugin developer wants a
    # generator group to fallback to another group in case of missing generators,
    # they can add a fallback.
    #
    # For example, shoulda is considered a test_framework and is an extension
    # of test_unit. However, most part of shoulda generators are similar to
    # test_unit ones.
    #
    # Shoulda then can tell generators to search for test_unit generators when
    # some of them are not available by adding a fallback:
    #
    #   Rails::Generators.fallbacks[:shoulda] = :test_unit
    #
    def self.fallbacks
      @fallbacks ||= {}
    end

    # Remove the color from output.
    def self.no_color!
      Thor::Base.shell = Thor::Shell::Basic
    end

    # Track all generators subclasses.
    def self.subclasses
      @subclasses ||= []
    end

    # Rails finds namespaces similar to thor, it only adds one rule:
    #
    # Generators names must end with "_generator.rb". This is required because Rails
    # looks in load paths and loads the generator just before it's going to be used.
    #
    # ==== Examples
    #
    #   find_by_namespace :webrat, :rails, :integration
    #
    # Will search for the following generators:
    #
    #   "rails:webrat", "webrat:integration", "webrat"
    #
    # Notice that "rails:generators:webrat" could be loaded as well, what
    # Rails looks for is the first and last parts of the namespace.
    #
    def self.find_by_namespace(name, base=nil, context=nil) #:nodoc:
      lookups = []
      lookups << "#{base}:#{name}"    if base
      lookups << "#{name}:#{context}" if context
      lookups << "#{name}:#{name}"    unless name.to_s.include?(?:)
      lookups << "#{name}"
      lookups << "rails:#{name}"      unless base || context || name.to_s.include?(?:)

      # Check if generator happens to be loaded
      klass = subclasses.find { |k| lookups.include?(k.namespace) }
      return klass if klass

      # Try to load generator from $LOAD_PATH
      checked = subclasses.dup
      lookup(lookups)

      unchecked = subclasses - checked
      klass     = unchecked.find { |k| lookups.include?(k.namespace) }
      return klass if klass

      invoke_fallbacks_for(name, base) || invoke_fallbacks_for(context, name)
    end

    # Receives a namespace, arguments and the behavior to invoke the generator.
    # It's used as the default entry point for generate, destroy and update
    # commands.
    def self.invoke(namespace, args=ARGV, config={})
      names = namespace.to_s.split(':')
      if klass = find_by_namespace(names.pop, names.shift)
        args << "--help" if args.empty? && klass.arguments.any? { |a| a.required? }
        klass.start(args, config)
      else
        puts "Could not find generator #{namespace}."
      end
    end

    # Show help message with available generators.
    def self.help
      builtin = Rails::Generators.builtin.each { |n| n.sub!(/^rails:/, '') }
      builtin.sort!

      # TODO Fix me
      # lookup("*")
      others  = subclasses.map{ |k| k.namespace }
      others -= Rails::Generators.builtin
      others.sort!

      puts "Please select a generator."
      puts "Builtin: #{builtin.join(', ')}."
      puts "Others: #{others.join(', ')}." unless others.empty?
    end

    protected

      # Keep builtin generators in an Array.
      def self.builtin #:nodoc:
        Dir[File.dirname(__FILE__) + '/generators/*/*'].collect do |file|
          file.split('/')[-2, 2].join(':')
        end
      end

      # Try fallbacks for the given base.
      def self.invoke_fallbacks_for(name, base) #:nodoc:
        return nil unless base && fallbacks[base.to_sym]
        invoked_fallbacks = []

        Array(fallbacks[base.to_sym]).each do |fallback|
          next if invoked_fallbacks.include?(fallback)
          invoked_fallbacks << fallback

          klass = find_by_namespace(name, fallback)
          return klass if klass
        end

        nil
      end

      # Receives namespaces in an array and tries to find matching generators
      # in the load path.
      def self.lookup(namespaces) #:nodoc:
        paths = namespaces_to_paths(namespaces)

        paths.each do |path|
          ["generators", "rails_generators"].each do |base|
            path = "#{base}/#{path}_generator"

            begin
              require path
              return
            rescue LoadError => e
              raise unless e.message =~ /#{Regexp.escape(path)}$/
            rescue NameError => e
              raise unless e.message =~ /Rails::Generator([\s(::)]|$)/
              warn "[WARNING] Could not load generator #{path.inspect} because it's a Rails 2.x generator, which is not supported anymore. Error: #{e.message}"
            end
          end
        end
      end

      # Convert namespaces to paths by replacing ":" for "/" and adding
      # an extra lookup. For example, "rails:model" should be searched
      # in both: "rails/model/model_generator" and "rails/model_generator".
      def self.namespaces_to_paths(namespaces) #:nodoc:
        paths = []
        namespaces.each do |namespace|
          pieces = namespace.split(":")
          paths << pieces.dup.push(pieces.last).join("/")
          paths << pieces.join("/")
        end
        paths.uniq!
        paths
      end

  end
end

