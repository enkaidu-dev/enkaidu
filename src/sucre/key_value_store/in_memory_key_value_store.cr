require "json"

module KeyValueStore
  alias Key = String
  alias Value = String
  alias Revision = Int64
  alias Namespace = String

  class NamedState
    getter name : Namespace
    getter revision : Revision

    @store : Hash(Key, Value)

    def initialize(@name)
      @store = {} of Key => Value
      @revision = 0
    end

    def set(key : Key, value : Value) : Void
      @store[key] = value
      @revision += 1
    end

    def get?(key : Key) : Value?
      @store[key]?
    end
  end

  # In-memory key/value store allows setting/getting key/value pairs grouped
  # by a namespace, with revision tracking in each namespace.
  class InMemory
    private getter state_hash = {} of String => NamedState

    def set(name : Namespace, key : Key, value : Value) : Void
      named_state = if state_hash.has_key?(name)
                      state_hash[name]
                    else
                      state_hash[name] = NamedState.new(name)
                    end
      named_state.set(key, value)
    end

    def get?(name : Namespace, key : Key) : Value?
      state_hash[name]?.try(&.get?(key))
    end

    def revision(name : Namespace) : Revision
      state_hash[name]?.try(&.revision) || 0_i64
    end

    def namespaces
      state_hash.keys
    end
  end
end
