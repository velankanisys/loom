#
# Cookbook Name:: hadoop
# Recipe:: hadoop_hdfs_namenode
#
# Copyright (C) 2013 Continuuity, Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'hadoop::default'
include_recipe 'hadoop::hadoop_hdfs_checkconfig'

package "hadoop-hdfs-namenode" do
  action :install
end

dfs_name_dirs =
  if (node['hadoop'].has_key? 'hdfs_site' and node['hadoop']['hdfs_site'].has_key? 'dfs.name.dir')
    node['hadoop']['hdfs_site']['dfs.name.dir']
  else
    "/tmp/hadoop-hdfs/dfs/name"
  end

node.default['hadoop']['hdfs_site']['dfs.name.dir'] = dfs_name_dirs

dfs_name_dirs.split(',').each do |dir|
  directory dir do
    mode 0700
    owner "hdfs"
    group "hdfs"
    action :create
    recursive true
  end
end

# Are we HA?
if (node['hadoop'].has_key? 'hdfs_site' and node['hadoop']['hdfs_site'].has_key? 'dfs.ha.automatic-failover.enabled' \
  and node['hadoop']['hdfs_site']['dfs.ha.automatic-failover.enabled'] == true)
  include_recipe 'hadoop::hadoop_hdfs_ha_checkconfig'
  include_recipe 'hadoop::hadoop_hdfs_zkfc'
end

service "hadoop-hdfs-namenode" do
  action :nothing
end

execute "hdfs-namenode-format" do
  command "hdfs namenode -format"
  action :nothing
  group "hdfs"
  user "hdfs"
end

execute "hdfs-namenode-bootstrap-standby" do
  command "hdfs namenode -bootstrapStandby"
  action :nothing
  group "hdfs"
  user "hdfs"
end

execute "hdfs-namenode-initialize-sharededits" do
  command "hdfs -initializeSharedEdits"
  action :nothing
  group "hdfs"
  user "hdfs"
end
