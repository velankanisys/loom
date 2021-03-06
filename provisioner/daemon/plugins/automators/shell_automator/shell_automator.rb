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

require 'net/scp'

class ShellAutomator < Automator
  attr_accessor :credentials, :scripts_dir, :scripts_tar, :remote_cache_dir

  def initialize(task)
    super(task)
    # local and remote top-level script directory name
    @scripts_parent_dir = "scripts"
    # local scripts dir
    @scripts_dir = "#{File.expand_path(File.dirname(__FILE__))}/#{@scripts_parent_dir}"
    # name of tarball to generate
    @scripts_tar = "#{File.expand_path(File.dirname(__FILE__))}/scripts.tar.gz"
    # remote storage directory
    @remote_cache_dir = "/var/cache/loom"
    # remote script location to be exported in $PATH
    @remote_scripts_dir = "#{@remote_cache_dir}/#{@scripts_parent_dir}"
  end

  def generate_scripts_tar
    if !File.exists?(@scripts_tar) or ((Time.now - File.stat(@scripts_tar).mtime).to_i > 600)
      log.debug "Generating #{@scripts_tar} from #{@scripts_dir}"
      scripts_tar_path = File.dirname(@scripts_dir)
      scripts_parent_dir = File.basename(@scripts_dir)
      `tar -czf "#{@scripts_tar}.new" -C "#{scripts_tar_path}" #{scripts_parent_dir}`
      `mv "#{@scripts_tar}.new" "#{@scripts_tar}"`
      log.debug "Generation complete: #{@scripts_tar}"
    end
  end

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

  def runshell(inputmap)
    sshauth = inputmap['sshauth']
    hostname = inputmap['hostname']
    ipaddress = inputmap['ipaddress']
    shellscript = inputmap['actionscript']
    shellargs = inputmap['actiondata']
    set_credentials(sshauth)

    begin
      Net::SSH.start(ipaddress, inputmap['sshauth']['user'], @credentials) do |ssh|
        log.debug "Running shell command: #{shellscript} #{shellargs}"
        output = ssh_exec!(ssh, "cd #{@remote_scripts_dir}; export PATH=$PATH:#{@remote_scripts_dir}; #{shellscript} #{shellargs}")
        if (output[2] != 0 )
          log.error "Shell command did not complete successfully: #{output}"
          raise "Shell command did not complete successfully: #{output}"
        end
        @result['stdout'] = output[0]
        @result['stderr'] = output[1]
      end
    rescue Net::SSH::AuthenticationFailed => e
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    @result['status'] = 0
    log.debug "Result of shell command: #{@result}"
    @result
  end

  def bootstrap(inputmap)
    sshauth = inputmap['sshauth']
    hostname = inputmap['hostname']
    ipaddress = inputmap['ipaddress']
    set_credentials(sshauth)

    generate_scripts_tar()

    begin
      Net::SSH.start(ipaddress, inputmap['sshauth']['user'], @credentials) do |ssh|

        # create @remote_cache_dir
        log.debug "Creating remote cache dir..."
        output = ssh_exec!(ssh, "mkdir -p #{@remote_cache_dir}")
        if (output[2] != 0 )
          log.error "Unable to create #{@remote_cache_dir} on #{hostname} : #{output}"
          raise "Unable to create #{@remote_cache_dir} on #{hostname} : #{output}"
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    log.debug "ShellAutomator bootstrap uploading scripts to #{ipaddress}"

    # scp tarball to target machine
    begin
      Net::SCP.upload!(ipaddress, sshauth["user"], "#{@scripts_tar}", "#{@remote_cache_dir}/scripts.tar.gz", :ssh =>
          @credentials, :verbose => true)
    rescue Net::SSH::AuthenticationFailed => e
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    # extract scripts tarball on remote machine
    begin
      Net::SSH.start(ipaddress, inputmap['sshauth']['user'], @credentials) do |ssh|
        output = ssh_exec!(ssh, "tar xf #{@remote_cache_dir}/scripts.tar.gz -C #{@remote_cache_dir}")
        if (output[2] != 0 )
          log.error "Error extracting remote #{@remote_cache_dir}/scripts.tar.gz: #{output}"
          raise "Error extracting remote #{@remote_cache_dir}/scripts.tar.gz: #{output}"
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      raise $!, "SSH Authentication failure for #{ipaddress}: #{$!}", $!.backtrace
    end

    @result['status'] = 0
    log.info "ShellAutomator bootstrap completed successfully: #{@result}"
  end

  def install(inputmap)
    runshell(inputmap)
  end

  def configure(inputmap)
    runshell(inputmap)
  end

  def init(inputmap)
    runshell(inputmap)
  end

  def start(inputmap)
    runshell(inputmap)
  end

  def stop(inputmap)
    runshell(inputmap)
  end

  def remove(inputmap)
    runshell(inputmap)
  end

end

