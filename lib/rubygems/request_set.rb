require 'rubygems'
require 'rubygems/dependency'
require 'rubygems/dependency_resolver'
require 'rubygems/dependency_list'
require 'rubygems/installer'
require 'tsort'

module Gem
  class RequestSet

    include TSort

    def initialize(*deps)
      @dependencies = deps

      yield self if block_given?
    end

    attr_reader :dependencies

    # Declare that a gem of name +name+ with +reqs+ requirements
    # is needed.
    #
    def gem(name, *reqs)
      @dependencies << Gem::Dependency.new(name, reqs)
    end

    # Resolve the requested dependencies and return an Array of
    # Specification objects to be activated.
    #
    def resolve(set=nil)
      r = Gem::DependencyResolver.new(@dependencies, set)
      @requests = r.resolve
    end

    # Load a Bundler-style Gemfile as much as possible.
    #
    def load_gemfile(path)
      gf = GemFile.new(self, path)
      gf.load
    end

    def specs
      @specs ||= @requests.map { |r| r.full_spec }
    end

    def tsort_each_node(&block)
      @requests.each(&block)
    end

    def tsort_each_child(node)
      node.spec.dependencies.each do |dep|
        next if dep.type == :development

        match = @requests.find { |r| dep.match? r.spec.name, r.spec.version }
        if match
          begin
            yield match
          rescue TSort::Cyclic
          end
        else
          raise Gem::DependencyError, "Unresolved depedency found during sorting - #{dep}"
        end
      end
    end

    def sorted_requests
      @sorted ||= strongly_connected_components.flatten
    end

    def specs_in(dir)
      Dir["#{dir}/specifications/*.gemspec"].map do |g|
        Gem::Specification.load g
      end
    end

    def install_into(dir, force=true)
      existing = force ? [] : specs_in(dir)

      dir = File.expand_path dir

      installed = []

      sorted_requests.each do |req|
        unless existing.find { |s| s.full_name == req.spec.full_name }
          path = req.download(dir)

          inst = Gem::Installer.new path, :install_dir => dir,
                                          :only_install_dir => true

          inst.install

          installed << req
        end
      end

      installed
    end

    # A semi-compatible DSL for Bundler's Gemfile format
    #
    class GemFile
      def initialize(set, path)
        @set = set
        @path = path
      end

      def load
        instance_eval File.read(@path), @path, 1
      end

      # DSL

      def source(url)
      end

      def gem(name, *reqs)
        # Ignore the opts for now.
        opts = reqs.pop if reqs.last.kind_of?(Hash)

        @set.gem name, *reqs
      end

      def platform(what)
        if what == :ruby
          yield
        end
      end

      alias_method :platforms, :platform

      def group(*what)
      end
    end
  end
end
