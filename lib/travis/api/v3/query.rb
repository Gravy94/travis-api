module Travis::API::V3
  class Query
    @@sidekiq_cache = Tool::ThreadLocal.new

    # generate from eval to avoid additional string allocations on every params access
    @@params_accessor = <<-RUBY
      attr_writer :%<name>s

      def %<name>s
        return @%<name>s if defined? @%<name>s
        return @%<name>s = @params['%<prefix>s.%<name>s'.freeze]            if @params.include? '%<prefix>s.%<name>s'.freeze
        return @%<name>s = @params['%<prefix>s'.freeze]['%<name>s'.freeze]  if @params.include? '%<prefix>s'.freeze and @params['%<prefix>s'.freeze].is_a? Hash
        return @%<name>s = @params['%<name>s'.freeze]                       if (@params['@type'.freeze] || @main_type) == '%<prefix>s'.freeze
        @%<name>s = nil
      end

      def %<name>s!
        %<name>s or raise WrongParams, 'missing %<prefix>s.%<name>s'.freeze
      end
    RUBY

    def self.params(*list, prefix: nil)
      prefix ||= name[/[^:]+$/].underscore
      list.each { |e| class_eval(@@params_accessor % { name: e, prefix: prefix }) }
    end

    attr_reader :params, :main_type

    def initialize(params, main_type)
      @params    = params
      @main_type = main_type.to_s
    end

    def perform_async(identifier, *args)
      Sidekiqs[identifier].perform_async(*args)
    end

    def includes?(key)
      @includes ||= @params['include'.freeze].to_s.split(?,.freeze)
      @includes.include? key
    end

    def bool(value)
      return false if value == 'false'.freeze
      !!value
    end

    def user_condition(value)
      case value
      when String       then { login: value    }
      when Integer      then { id:    value    }
      when Models::User then { id:    value.id }
      else raise WrongParams
      end
    end
  end
end
