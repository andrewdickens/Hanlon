#

require 'json'
require 'api_utils'

module Hanlon
  module WebService
    module Broker

      class APIv1 < Grape::API

        version :v1, :using => :path, :vendor => "hanlon"
        format :json
        default_format :json
        SLICE_REF = ProjectHanlon::Slice::Broker.new([])

        # Root namespace for broker objects
        # used to find them in object space for plugin checking
        BROKER_PREFIX = "ProjectHanlon::BrokerPlugin::"

        rescue_from ProjectHanlon::Error::Slice::InvalidUUID do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from Grape::Exceptions::Validation do |e|
          Rack::Response.new(
              Hanlon::WebService::Response.new(400, e.class.name, e.message).to_json,
              400,
              { "Content-type" => "application/json" }
          )
        end

        rescue_from :all do |e|
          #raise e
          Rack::Response.new(
              Hanlon::WebService::Response.new(500, e.class.name, e.message).to_json,
              500,
              { "Content-type" => "application/json" }
          )
        end

        helpers do

          def content_type_header
            settings[:content_types][env['api.format']]
          end

          def api_format
            env['api.format']
          end

          def is_uuid?(string_)
            string_ =~ /^[A-Za-z0-9]{1,22}$/
          end

          def get_data_ref
            Hanlon::WebService::Utils::get_data
          end

          def slice_success_response(slice, command, response, options = {})
            Hanlon::WebService::Utils::rz_slice_success_response(slice, command, response, options)
          end

          def slice_success_object(slice, command, response, options = {})
            Hanlon::WebService::Utils::rz_slice_success_object(slice, command, response, options)
          end

        end

        resource :broker do

          # GET /broker
          # Query for defined brokers.
          desc "Retrieve a list of all broker instances"
          get do
            brokers = SLICE_REF.get_object("broker_instances", :broker)
            slice_success_object(SLICE_REF, :get_all_brokers, brokers, :success_type => :generic)
          end     # end GET /broker

          # POST /broker
          # Create a Hanlon broker
          #   parameters:
          #     plugin            | String | The "plugin" to use for the new broker   |         | Default: unavailable
          #     name              | String | The "name" to use for the new broker     |         | Default: unavailable
          #     description       | String | The description of the new broker        |         | Default: unavailable
          #     req_metadata_hash | Hash   | The metadata to use for the new broker   |         | Default: unavailable
          desc "Create a new broker instance"
          params do
            requires "plugin", type: String, desc: "The broker plugin to use"
            requires "name", type: String, desc: "The new broker's name"
            requires "description", type: String, desc: "The new broker's description"
            requires "req_metadata_hash", type: Hash, desc: "The metadata hash to use"
          end
          post do
            plugin = params["plugin"]
            name = params["name"]
            description = params["description"]
            req_metadata_hash = params["req_metadata_hash"]
            # use the arguments passed in to create a new broker
            broker = SLICE_REF.new_object_from_template_name(BROKER_PREFIX, plugin)
            raise ProjectHanlon::Error::Slice::MissingArgument, "Must Provide Required Metadata [req_metadata_hash]" unless
                req_metadata_hash
            broker.name             = name
            broker.user_description = description
            broker.is_template      = false
            broker.req_metadata_hash.each { |key, md_hash_value|
              value = params[key]
              broker.set_metadata_value(key, value, md_hash_value[:validation])
            }
            broker.req_metadata_hash = req_metadata_hash
            # persist that broker, and print the result (or raise an error if cannot persist it)
            get_data_ref.persist_object(broker)
            raise(ProjectHanlon::Error::Slice::CouldNotCreate, "Could not create Broker Target") unless broker
            slice_success_object(SLICE_REF, :create_broker, broker, :success_type => :created)
          end     # end POST /broker

          resource :plugins do

            # GET /broker/plugins
            # Query for available broker plugins
            desc "Retrieve a list of available broker plugins"
            get do
              # get the broker plugins (as an array)
              broker_plugins = SLICE_REF.get_child_templates(ProjectHanlon::BrokerPlugin)
              # then, construct the response
              slice_success_object(SLICE_REF, :get_broker_plugins, broker_plugins, :success_type => :generic)
            end     # end GET /broker/plugins

            resource '/:name' do

              # GET /broker/plugins/{name}
              # Query for a specific broker plugin (by name)
              desc "Retrieve details for a specific broker plugin (by name)"
              params do
                requires :name, type: String, desc: "The name of the plugin"
              end
              get do
                # get the matching broker plugin
                broker_plugin_name = params[:name]
                broker_plugins = SLICE_REF.get_child_templates(ProjectHanlon::BrokerPlugin)
                broker_plugin = broker_plugins.select { |plugin| plugin.plugin.to_s == broker_plugin_name }
                raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Broker Plugin Named: [#{broker_plugin_name}]" unless broker_plugin && (broker_plugin.class != Array || broker_plugin.length > 0)
                # then, construct the response
                slice_success_object(SLICE_REF, :get_broker_plugin_by_uuid, broker_plugin[0], :success_type => :generic)
              end     # end GET /broker/plugins/{uuid}

            end     # end resource /broker/plugins/:uuid

          end     # end resource /broker/plugins

          resource '/:uuid' do

            # GET /broker/{uuid}
            # Query for the state of a specific broker.
            desc "Retrieve details for a specific broker instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The broker's UUID"
            end
            get do
              broker_uuid = params[:uuid]
              broker = SLICE_REF.get_object("broker instances", :broker, broker_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Broker Target UUID: [#{broker_uuid}]" unless broker && (broker.class != Array || broker.length > 0)
              slice_success_object(SLICE_REF, :get_broker_by_uuid, broker, :success_type => :generic)
            end     # end GET /broker/{uuid}

            # PUT /broker/{uuid}
            # Update a Hanlon broker (any of the the name, description, or req_metadata_hash
            # can be updated using this endpoint; note that the broker plugin cannot be updated
            # once a broker is created
            #   parameters:
            #     name              | String | The "name" to use for the new broker     |         | Default: unavailable
            #     description       | String | The description of the new broker        |         | Default: unavailable
            #     req_metadata_hash | Hash   | The metadata to use for the new broker   |         | Default: unavailable
            desc "Update a broker instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The broker's UUID"
              optional "name", type: String, desc: "The broker's new name"
              optional "description", type: String, desc: "The broker's new description"
              optional "req_metadata_hash", type: Hash, desc: "The new metadata hash"
            end
            put do
              # get the input parameters that were passed in as part of the request
              # (at least one of these should be a non-nil value)
              broker_uuid = params[:uuid]
              plugin = params[:plugin]
              name = params[:name]
              description = params[:description]
              req_metadata_hash = params[:req_metadata_hash]
              # check the values that were passed in (and gather new meta-data if
              # the --change-metadata flag was included in the update command and the
              # command was invoked via the CLI...it's an error to use this flag via
              # the RESTful API, the req_metadata_hash should be used instead)
              broker = SLICE_REF.get_object("broker_with_uuid", :broker, broker_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Invalid Broker UUID [#{broker_uuid}]" unless broker && (broker.class != Array || broker.length > 0)
              # fill in the fields with the new values that were passed in (if any)
              broker.name              = name if name
              broker.user_description  = description if description
              broker.is_template       = false
              if req_metadata_hash
                req_metadata_hash.each { |key, md_hash_value|
                  value = params[key]
                  broker.set_metadata_value(key, value, md_hash_value[:validation])
                }
                broker.req_metadata_hash = req_metadata_hash
              end
              raise ProjectHanlon::Error::Slice::CouldNotUpdate, "Could not update Broker Target [#{broker.uuid}]" unless broker.update_self
              slice_success_object(SLICE_REF, :update_broker, broker, :success_type => :updated)
            end     # end PUT /broker/{uuid}

            # DELETE /broker/{uuid}
            # Remove a Hanlon broker (by UUID)
            desc "Remove a broker instance (by UUID)"
            params do
              requires :uuid, type: String, desc: "The broker's UUID"
            end
            delete do
              broker_uuid = params[:uuid]
              broker = SLICE_REF.get_object("broker_with_uuid", :broker, broker_uuid)
              raise ProjectHanlon::Error::Slice::InvalidUUID, "Cannot Find Broker with UUID: [#{broker_uuid}]" unless broker && (broker.class != Array || broker.length > 0)
              raise ProjectHanlon::Error::Slice::CouldNotRemove, "Could not remove Broker [#{broker.uuid}]" unless get_data_ref.delete_object(broker)
              slice_success_response(SLICE_REF, :remove_broker_by_uuid, "Broker [#{broker.uuid}] removed", :success_type => :removed)
            end     # end DELETE /broker/{uuid}

          end     # end resource /broker/:uuid

        end     # end resource /broker

      end

    end

  end

end
