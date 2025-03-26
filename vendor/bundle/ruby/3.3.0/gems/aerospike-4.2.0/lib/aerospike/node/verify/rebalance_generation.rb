# frozen_string_literal: true

# Copyright 2018 Aerospike, Inc.
#
# Portions may be licensed to Aerospike, Inc. under one or more contributor
# license agreements.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

module Aerospike
  class Node
    module Verify
      # Fetch and set rebalance generation. If racks needs to be refreshed
      # this will be indicated in node.rebalance_changed
      module RebalanceGeneration
        class << self
          def call(node, info_map)
            gen_string = info_map.fetch('rebalance-generation', nil)

            raise Aerospike::Exceptions::Parse.new('rebalance-generation is empty', node) if gen_string.to_s.empty?

            generation = gen_string.to_i

            node.rebalance_generation.update(generation)

            return unless node.rebalance_generation.changed?
            Aerospike.logger.info("Node #{node.name} rebalance generation #{generation} changed")
          end
        end
      end
    end
  end
end
