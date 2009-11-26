# This is the class loader, for use as "include Redis::Objects::Locks"
# For the object itself, see "Redis::Lock"
require 'redis/lock'
class Redis
  module Objects
    class UndefinedLock < StandardError; end #:nodoc:
    module Locks
      def self.included(klass)
        klass.instance_variable_set('@locks', {})
        klass.send :include, InstanceMethods
        klass.extend ClassMethods
      end

      # Class methods that appear in your class when you include Redis::Objects.
      module ClassMethods
        attr_reader :locks

        # Define a new lock.  It will function like a model attribute,
        # so it can be used alongside ActiveRecord/DataMapper, etc.
        def lock(name, options={})
          options[:timeout] ||= 5  # seconds
          @locks[name] = options
          class_eval <<-EndMethods
            def #{name}_lock(&block)
              @#{name}_lock ||= Redis::Lock.new(field_key(:#{name}_lock), redis, self.class.locks[:#{name}])
            end
          EndMethods
        end

        # Obtain a lock, and execute the block synchronously.  Any other code
        # (on any server) will spin waiting for the lock up to the :timeout
        # that was specified when the lock was defined.
        def obtain_lock(name, id, &block)
          verify_lock_defined!(name)
          raise ArgumentError, "Missing block to #{self.name}.obtain_lock" unless block_given?
          lock_name = field_key("#{name}_lock", id)
          Redis::Lock.new(redis, lock_name, self.class.locks[name]).lock(&block)
        end

        # Clear the lock.  Use with care - usually only in an Admin page to clear
        # stale locks (a stale lock should only happen if a server crashes.)
        def clear_lock(name, id)
          verify_lock_defined!(name)
          lock_name = field_key("#{name}_lock", id)
          redis.del(lock_name)
        end
        
        private
        
        def verify_lock_defined!(name)
          raise Redis::Objects::UndefinedLock, "Undefined lock :#{name} for class #{self.name}" unless @locks.has_key?(name)
        end
      end
    end
  end
end
