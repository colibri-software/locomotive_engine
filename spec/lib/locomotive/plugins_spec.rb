require 'spec_helper'

module Locomotive
  module Plugins
    describe Processor do

      before(:each) do
        @enabled_plugin = register_and_enable_plugin(MyEnabledPlugin)
        @disabled_plugin = register_plugin(MyDisabledPlugin)

        @site = FactoryGirl.build(:site)
        @site.stubs(:enabled_plugins).returns(@enabled_plugins)

        Locomotive::TestController.send(:include, Locomotive::Plugins::Processor)
        @controller = Locomotive::TestController.new
        @controller.stubs(:current_site).returns(@site)
      end

      context 'before_filters' do

        it 'should run all before_filters for enabled plugins' do
          @enabled_plugin.expects(:my_method)
          @controller.process_plugins
        end

        it 'should not run any before_filters for disabled plugins' do
          @disabled_plugin.expects(:another_method).never
          @controller.process_plugins
        end

        it 'should be able to access the controller from the before_filter' do
          @controller.expects(:params)
          @controller.process_plugins
        end

      end

      context 'liquid' do

        before(:each) do
          @another_enabled_plugin = register_and_enable_plugin(AnotherEnabledPlugin)
          @controller.process_plugins
        end

        it 'should supply the enabled plugins' do
          @controller.enabled_plugins.should == [ @enabled_plugin, @another_enabled_plugin ]
          @enabled_plugins.clear
          @controller.process_plugins
          @controller.enabled_plugins.should == []
        end

        it 'should build a container for the plugin liquid drops' do
          container = @controller.plugin_drops_container
          container_liquid = container.to_liquid
          container_liquid.kind_of?(::Liquid::Drop).should be_true
        end

        it 'should retrieve the liquid drops for enabled plugins with drops' do
          container = @controller.plugin_drops_container
          container['my_enabled_plugin'].should == @enabled_plugin.to_liquid
          container['another_enabled_plugin'].should be_nil
        end

        it 'should not retrieve the liquid drops for disabled plugins' do
          container = @controller.plugin_drops_container
          container['my_disabled_plugin'].should be_nil
        end

      end

      protected

      def register_plugin(plugin_class)
        LocomotivePlugins.register_plugin(plugin_class)
        plugin_id = LocomotivePlugins.default_id(plugin_class)
        LocomotivePlugins.registered_plugins[plugin_id]
      end

      def enable_plugin(plugin_id)
        @enabled_plugins ||= []
        @enabled_plugins << plugin_id
      end

      def register_and_enable_plugin(plugin_class)
        plugin_id = LocomotivePlugins.default_id(plugin_class)
        enable_plugin(plugin_id)
        register_plugin(plugin_class)
      end

      ## Classes ##

      class MyEnabledPlugin

        include Locomotive::Plugin

        before_filter :my_method

        def to_liquid
          @my_drop ||= MyEnabledDrop.new
        end

        def my_method
          # Access params
          self.controller.params
        end

      end

      class AnotherEnabledPlugin
        include Locomotive::Plugin
      end

      class PluginWithScope
        include Locomotive::Plugin
      end

      class MyDisabledPlugin

        include Locomotive::Plugin

        before_filter :another_method

        def another_method
        end

        def to_liquid
          @my_drop ||= MyDisabledDrop.new
        end

      end

      class MyEnabledDrop < ::Liquid::Drop
      end

      class MyDisabledDrop < ::Liquid::Drop
      end

    end
  end
end