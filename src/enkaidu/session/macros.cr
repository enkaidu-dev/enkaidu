module Enkaidu
  class Session
    module Macros
      # Locate a macro by name, prioritizing config macros with the same name over
      # profile ones.
      def find_macro_by_name?(name) : Config::Macro?
        ((macros = opts.config.try(&.macros)) && macros[name]?) || opts.profile.macros[name]?
      end

      # Traverse macros, prioritizing config macros with the same name over
      # profile ones.
      private def each_macro(&)
        if config_macros = opts.config.try(&.macros)
          config_macros.each do |name, mac|
            yield name, mac, "Config"
          end
          opts.profile.macros.each do |name, mac|
            # Macro with same name in config file supercedes profile
            yield name, mac, "Profile" unless config_macros[name]?
          end
        else
          opts.profile.macros.each do |name, mac|
            yield name, mac, "Profile"
          end
        end
      end

      def list_all_macros
        text = String.build do |io|
          each_macro do |name, mac, origin|
            io << "**" << name << "** (" << origin << "): "
            io << mac.description << "\n\n"
          end
          io << '\n'
        end
        renderer.info_with("List of available macros.", text, markdown: true)
      end
    end
  end
end
