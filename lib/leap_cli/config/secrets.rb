#
#
# A class for the secrets.json file
#
#

module LeapCli; module Config

  class Secrets < Object
    attr_reader :node_list

    def initialize(manager=nil)
      super(manager)
      @discovered_keys = {}
    end

    def set(key, value)
      key = key.to_s
      @discovered_keys[key] = true
      self[key] ||= value
    end

    #
    # if only_discovered_keys is true, then we will only export
    # those secrets that have been discovered and the prior ones will be cleaned out.
    #
    # this should only be triggered when all nodes have been processed, otherwise
    # secrets that are actually in use will get mistakenly removed.
    #
    #
    def dump_json(only_discovered_keys=false)
      if only_discovered_keys
        self.each_key do |key|
          unless @discovered_keys[key]
            self.delete(key)
          end
        end
      end
      super()
    end
  end

end; end
