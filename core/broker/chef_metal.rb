# Our chef-metal plugin which contains the agent & device proxy classes used for hand off
# The primary difference between this and the normal Chef broker is that metal already
# knows and has generated Chef data for the nodes and builds a 1:1 mapping between
# Hanlon and a node, so here we just need the client key and the node name
# along with some tweaks to the bootstrap script and some extra data.

require "erb"
require "net/ssh"
require 'digest/md5'
require 'uri'

require 'broker/chef'

# Root namespace for ProjectHanlon
module ProjectHanlon::BrokerPlugin

  # Root namespace for chef-metal Broker plugin defined in ProjectHanlon for node handoff
  class ChefMetal < ProjectHanlon::BrokerPlugin::Chef
    include(ProjectHanlon::Logging)

    def initialize(hash)
      super(hash)

      @plugin = :chef_metal
      @description = "Opscode chef-metal \\m/"
      @hidden = false
      from_hash(hash) if hash
      @req_metadata_hash = {
        "@chef_server_url" => {
          :default      => "",
          :example      => "https://chef.example.com:4000",
          :validation   => URI::regexp.to_s,
          :required     => true,
          :description  => "the URL for the Chef server."
        },
        "@chef_version" => {
          :default      => "",
          :example      => "10.16.2",
          :validation   => '^[0-9]+\.[0-9]+\.[0-9]+(\.[a-zA-Z0-9\.]+)?$',
          :required     => true,
          :description  => "the Chef version (used in gem install)."
        },
        "@node_name" => {
          :default      => "",
          :example      => "web00",
          :validation   => '^[\w._-]+$',
          :required     => true,
          :description  => "The node's name"
        },
        "@client_key" => {
          :default      => '',
          :example      => "Foo",
          # TODO: make this better.
          :validation   => '.*',
          :required     => true,
          :description  => "The client's PEM-encoded key"
        },
        "@install_sh_url" => {
          :default      => "http://opscode.com/chef/install.sh",
          :example      => "http://mirror.example.com/install.sh",
          :validation   => URI::regexp.to_s,
          :required     => true,
          :description  => "the Omnibus installer script URL."
        },
        "@chef_client_path" => {
          :default      => "chef-client",
          :example      => "/usr/local/bin/chef-client",
          :validation   => '^[\w._-]+$',
          :required     => true,
          :description  => "an alternate path to the chef-client binary."
        }
      }
    end

    def print_item_header
      if @is_template
        return "Plugin", "Description"
      else
        return "Name", "Description", "Plugin", "UUID", "Chef Server URL", "Chef Version", "Client Key MD5",
                "Node Name",  "install.sh URL", "Chef Client Path", "Base Run List"
      end
    end

    def print_item
      if @is_template
        return @plugin.to_s, @description.to_s
      else
        return @name, @user_description, @plugin.to_s, @uuid, @chef_server_url, @chef_version, Digest::MD5.hexdigest(@client_key),
               @node_name, @install_sh_url, @chef_client_path, @base_run_list
      end
    end

    def compile_template
      logger.debug "Compiling template"
      install_script = File.join(File.dirname(__FILE__), "chef/chef_metal_bootstrap.erb")
      contents = ERB.new(File.read(install_script)).result(binding)
      logger.debug "Chef-metal bootstrap script:\n---\n#{contents}\n---"
      contents
    end

    private

    BROKER_SUCCESS_MSG = "Hanlon Chef-metal bootstrap completed."

    attr_reader :install_sh_url, :chef_version, :client_key, :base_run_list

    def config_content
      <<-CONFIG.gsub(/^ +/, '')
        log_level               :info
        log_location            STDOUT
        chef_server_url         "#{@chef_server_url}"
        node_name               "#{@node_name}"
        ssl_verify_mode         :verify_none
        client_key              "/etc/chef/client.pem"
      CONFIG
    end

    def start_chef
      [ %{#{@chef_client_path}},
        %{echo "#{BROKER_SUCCESS_MSG}"}
      ].join("\n")
    end
  end
end
