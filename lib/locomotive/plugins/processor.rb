
module Locomotive
  module Plugins
    module Processor

      attr_accessor :plugin_drops_container

      def process_plugins
        plugin_drops_container_hash = {}
        each_enabled_plugin do |plugin_id, plugin|
          plugin.controller = self

          # Call all before_filters
          plugin.before_filters.each do |meth|
            plugin.send(meth)
          end

          # Add the drop to the container
          drop = plugin.to_liquid
          plugin_drops_container_hash[plugin_id] = drop if drop
        end

        self.plugin_drops_container = DropContainer.new(plugin_drops_container_hash)
      end

      def enabled_plugins
        [].tap do |plugins|
          each_enabled_plugin do |plugin_id, plugin|
            plugins << plugin
          end
        end
      end

      protected

      def each_enabled_plugin
        current_site.enabled_plugins.each do |plugin_id|
          plugin = LocomotivePlugins.registered_plugins[plugin_id]
          yield plugin_id, plugin
        end
      end

    end
  end
end