
class PluginClass
  include Locomotive::Plugin

  class Drop < ::Liquid::Drop
    attr_accessor :greeting
  end

  module Filters
    def add_http_prefix(input)
      if input.start_with?('http://')
        input
      else
        "http://#{input}"
      end
    end
  end

  before_filter :set_greeting

  def to_liquid
    @drop ||= Drop.new
  end
  alias :drop :to_liquid

  def config_template_file
    # Rails root is at spec/dummy
    engine_root = Rails.root.join('..', '..')
    engine_root.join('spec', 'fixtures', 'assets', 'plugin_config_template.html.haml')
  end

  def liquid_filters
    Filters
  end

  def set_greeting
    self.drop.greeting = 'Hello, World!'
  end

end

Given /^I have registered the plugin "(.*)"$/ do |plugin_id|
  LocomotivePlugins.register_plugin(PluginClass, plugin_id)
end

Given /^the plugin "(.*)" is enabled$/ do |plugin_id|
  plugin_data = @site.reload.plugin_data.detect do |plugin_data|
    plugin_data.plugin_id == plugin_id
  end

  if plugin_data
    plugin_data.enabled = true
    @site.save!
  else
    FactoryGirl.create(:plugin_data,
                       :plugin_id => plugin_id,
                       :enabled => true,
                       :site => @site)
  end
end

Given /^the plugin "(.*)" is disabled$/ do |plugin_id|
  plugin_data = @site.reload.plugin_data.detect do |plugin_data|
    plugin_data.plugin_id == plugin_id
  end

  if plugin_data
    plugin_data.enabled = false
    @site.save!
  end
end

Then /^the plugin "(.*)" should be enabled$/ do |plugin_id|
  enabled_plugin_ids = @site.reload.plugin_data.select do |plugin_data|
    plugin_data.enabled
  end.collect(&:plugin_id)
  enabled_plugin_ids.should include(plugin_id)
end

Then /^the plugin config for "(.*)" should be:$/ do |plugin_id, table|
  @site.reload

  # Force site to recreate plugin objects
  @site.instance_variable_set(:@all_plugin_objects_by_id, nil)
  @site.instance_variable_set(:@enabled_plugin_objects_by_id, nil)
  @site.instance_variable_set(:@plugin_data_by_id, nil)

  plugin = @site.all_plugin_objects_by_id[plugin_id]
  plugin.config.should == table.rows_hash
end