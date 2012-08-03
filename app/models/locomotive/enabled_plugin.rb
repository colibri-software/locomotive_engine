module Locomotive
  class EnabledPlugin

    include Locomotive::Mongoid::Document

    ## fields ##
    field :plugin_id
    field :config, :type => Hash

    ## relationships ##

    embedded_in :site, :class_name => 'Locomotive::Site'

    ## methods ##

    def plugin_class
      LocomotivePlugins.registered_plugins[self.plugin_id]
    end

  end
end