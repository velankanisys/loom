#!/usr/bin/env ruby
#
# Copyright 2012-2014, Continuuity, Inc.
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

gem 'knife-rackspace', '= 0.8.4'

require 'json'
require_relative 'chef/knife/loom_rackspace_server_create'
require_relative 'chef/knife/loom_rackspace_server_confirm'
require 'chef/knife/rackspace_server_delete'

class RackspaceProvider < Provider

  def create(inputmap)
    flavor = inputmap['flavor']
    image = inputmap['image']
    hostname = inputmap['hostname']

    begin
      knife_instance = Chef::Knife::LoomRackspaceServerCreate.new
      knife_instance.configure_chef

      Chef::Config[:knife][:flavor] = flavor
      Chef::Config[:knife][:image] = image
      knife_instance.config[:chef_node_name] = hostname

      Chef::Config[:knife][:rackspace_username] = @task["config"]["provider"]["provisioner"]["auth"]["rackspace_username"]
      Chef::Config[:knife][:rackspace_api_key] = @task["config"]["provider"]["provisioner"]["auth"]["rackspace_api_key"]

      # invoke knife
      log.debug "Invoking server create"
      kniferesult = knife_instance.run
      @result['result']['providerid'] = kniferesult['providerid']
      @result['result']['ssh-auth']['user'] = "root"
      @result['result']['ssh-auth']['password'] = kniferesult['rootpassword']
      @result['status'] = kniferesult['status']

    rescue Exception => e
      log.error('Unexpected Error Occured in RackspaceProvider.create:' + e.inspect)
      @result['stderr'] = "Unexpected Error Occured in RackspaceProvider.create: #{e.inspect}"
    else
      log.debug "Create finished successfully: #{@result}"
    ensure
      @result['status'] = 1 if @result['status'].nil? || (@result['status'].is_a?(Hash) && @result['status'].empty?)
    end
  end

  def confirm(inputmap)
    providerid = inputmap['providerid']

    begin
      knife_instance = Chef::Knife::LoomRackspaceServerConfirm.new
      knife_instance.configure_chef
      knife_instance.name_args.push(providerid)

      Chef::Config[:knife][:rackspace_username] = @task["config"]["provider"]["provisioner"]["auth"]["rackspace_username"]
      Chef::Config[:knife][:rackspace_api_key] = @task["config"]["provider"]["provisioner"]["auth"]["rackspace_api_key"]

      # invoke knife
      log.debug "Invoking server confirm"
      kniferesult = knife_instance.run

      @result['result']['ipaddress'] = kniferesult['ipaddress']
      raise "non-zero exit code: #{kniferesult['status']} from knife rackspace" unless kniferesult['status'] == 0

      # additional checks, we want to make sure we can login and verify external dns
      log.debug "Confirming ssh is up"
      knife_instance.tcp_test_ssh(kniferesult['ipaddress']) { sleep 5 }
      set_credentials(@task['config']['ssh-auth'])

      Net::SSH.start(kniferesult['ipaddress'], @task['config']['ssh-auth']['user'], @credentials) do |ssh|
        # validate connectivity
        log.debug "Validating dns resolution/connectivity"
        output = ssh_exec!(ssh, "ping -c1 www.opscode.com")
      end

      @result['status'] = 0

    rescue Net::SSH::AuthenticationFailed => e
      log.error("SSH Authentication failure for #{providerid}/#{kniferesult['ipaddress']}")
      @result['stderr'] = "SSH Authentication failure for #{providerid}/#{kniferesult['ipaddress']}: #{e.inspect}"
    rescue Exception => e
      log.error('Unexpected Error Occured in RackspaceProvider.confirm:' + e.inspect)
      @result['stderr'] = "Unexpected Error Occured in RackspaceProvider.confirm: #{e.inspect}"
    else
      log.debug "Confirm finished successfully: #{@result}"
    ensure
      @result['status'] = 1 if @result['status'].nil? || (@result['status'].is_a?(Hash) && @result['status'].empty?)
    end
  end

  def delete(inputmap)
    providerid = inputmap['providerid']

    begin
      knife_instance = Chef::Knife::RackspaceServerDelete.new
      knife_instance.configure_chef
      knife_instance.name_args.push(@task["config"]["providerid"])
      knife_instance.config[:yes] = true

      Chef::Config[:knife][:rackspace_username] = @task["config"]["provider"]["provisioner"]["auth"]["rackspace_username"]
      Chef::Config[:knife][:rackspace_api_key] = @task["config"]["provider"]["provisioner"]["auth"]["rackspace_api_key"]

      # invoke knife
      log.debug "Invoking server delete"
      kniferesult = knife_instance.run

      @result['status'] = 0

    rescue Exception => e
      log.error('Unexpected Error Occured in RackspaceProvider.delete:' + e.inspect)
      @result['stderr'] = "Unexpected Error Occured in RackspaceProvider.delete: #{e.inspect}"
    else
      log.debug "Delete finished sucessfully: #{@result}"
    ensure
      @result['status'] = 1 if @result['status'].nil? || (@result['status'].is_a?(Hash) && @result['status'].empty?)
    end
  end

  # used by ssh validation in confirm stage
  def set_credentials(sshauth)
    @credentials = Hash.new
    @credentials[:paranoid] = false
    sshauth.each do |k, v|
      if (k =~ /password/)
        @credentials[:password] = v
      elsif (k =~ /identityfile/)
        @credentials[:keys] = [ v ]
      end
    end
  end

end

  
