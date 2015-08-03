#
# Copyright:: Copyright (c) 2015 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef-dk/service_exceptions'
require 'chef-dk/authenticated_http'

module ChefDK
  module PolicyfileServices

    class UndoRecord

      PolicyGroupRestoreData = Struct.new(:policy_name, :policy_group, :data)

      attr_reader :policy_groups

      attr_reader :policy_revisions

      def initialize
        @policy_groups = []
        @policy_revisions = []
      end

      def add_policy_group(name)
        @policy_groups << name
      end

      def add_policy_revision(policy_name, policy_group, data)
        @policy_revisions << PolicyGroupRestoreData.new(policy_name, policy_group, data)
      end

      def commit!
        raise NotImplementedError, "TODO"
      end

    end

    class RmPolicyGroup

      attr_reader :policy_group

      # @api private
      attr_reader :chef_config

      # @api private
      attr_reader :ui

      # @api private
      attr_reader :undo_record

      def initialize(config: nil, ui: nil, policy_group: nil)
        @chef_config = config
        @ui = ui
        @policy_group = policy_group

        @undo_record = UndoRecord.new
      end

      def run

        policy_group_list = http_client.get("/policy_groups")

        unless policy_group_list.has_key?(policy_group)
          ui.err("Policy group '#{policy_group}' does not exist on the server")
          return false
        end
        policies_in_group = policy_group_list[policy_group]
        policies_in_group.each do |name, rev_id|
          policy_revision_data = http_client.get("/policies/#{name}/revisions/#{rev_id}")
          undo_record.add_policy_revision(name, policy_group, policy_revision_data)
        end
        http_client.delete("/policy_groups/#{policy_group}")
        undo_record.add_policy_group(policy_group)
        ui.err("Removed policy group '#{policy_group}'.")
        undo_record.commit!
      rescue => e
        raise DeletePolicyGroupError.new("Failed to delete policy group '#{policy_group}'", e)
      end

      # @api private
      # An instance of ChefDK::AuthenticatedHTTP configured with the user's
      # server URL and credentials.
      def http_client
        @http_client ||= ChefDK::AuthenticatedHTTP.new(chef_config.chef_server_url,
                                                       signing_key_filename: chef_config.client_key,
                                                       client_name: chef_config.node_name)
      end
    end
  end
end

