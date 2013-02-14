
require 'spec_helper'

module Locomotive
  module Plugins
    describe RackAppPassthrough do

      let(:site) do
        Locomotive::Plugins::SpecHelpers.before_each(__FILE__)

        # Make sure the site we're using isn't the first one in the DB
        FactoryGirl.create(:site)
        FactoryGirl.create(:site, subdomain: 'my-subdomain')
      end

      it 'should fetch the correct site' do
        Locomotive.config.stubs(:multi_sites).returns(true)
        RackAppPassthrough.fetch_site(site.domains.first).should == site

        Locomotive.config.stubs(:multi_sites).returns(false)
        RackAppPassthrough.fetch_site(site.domains.first).should ==
          Locomotive::Site.first

        Locomotive::Site.first.should_not == site
      end

      it 'should get a nil site for a subdomain which doesn\'t exist' do
        Locomotive.config.stubs(:multi_sites).returns(true)
        RackAppPassthrough.fetch_site('unknown-subdomain').should be_nil
      end

      it 'should get the prepared Rack app wrapper, not the raw Rack app' do
        RackAppPassthrough.stubs(:fetch_site).returns(site)

        plugin = PluginWithRackApp.new
        plugin_id = plugin.class.default_plugin_id

        plugin_data = FactoryGirl.create(:plugin_data, plugin_id: plugin_id,
          enabled: true, site: site)

        env = {
          'action_dispatch.request.path_parameters' => {
            :plugin_id => plugin_id
          }
        }

        app = RackAppPassthrough.get_app(env)
        app.should_not == PluginWithRackApp::RackApp
        app.class.should == plugin.prepared_rack_app.class

        wrapped_app = app.instance_variable_get(:@app)
        wrapped_app.should == PluginWithRackApp::RackApp
        wrapped_app.plugin_object.should == plugin

        plugin_data.enabled = false
        plugin_data.save!
        site.reload

        app = RackAppPassthrough.get_app(env)
        app.should be_nil
      end

      protected

      Locomotive::Plugins::SpecHelpers.define_plugins(__FILE__) do
        class PluginWithRackApp
          include Locomotive::Plugin

          def self.rack_app
            RackApp
          end

          class RackApp
            def self.call(env)
              [200, {}, []]
            end
          end
        end
      end

    end
  end
end
