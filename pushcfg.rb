# require 'pry'
require 'sinatra'
require 'cocaine'
require 'pathname'
require 'json'

module Cfg
  def install
    @boot_cfg = Pushcfg::MATCHBOX_DIR + 'groups'
    @boot_cfg.mkpath
    (@boot_cfg + 'node1.json').expand_path.exist? ? next_node : create_cfg
  end

  def next_node
    read_cfg
    node = @nodes.find{ |n| n['selector']['mac'].downcase == mac_addr.downcase }
    unless node
      @id = (@boot_cfg.expand_path.children.size + 1).to_s
      (@boot_cfg + "node#{@id}.json").expand_path.write(JSON.dump(bk_node_cfg))
    end
  end

  def read_cfg
    @nodes = []
    @boot_cfg.expand_path.children.each { |c| @nodes << JSON.load(c.read) }
  end

  def create_cfg
    (@boot_cfg + 'node1.json').expand_path.write(JSON.dump(bk_controller_cfg))
  end

  def bk_controller_cfg
    cfg = bk_controller.dup
    id = 'node1'
    etcd_init = "#{id}=http://" + id + '.' + domain + ':2380'
    cfg['selector']['mac'] = mac_addr
    cfg['metadata']['domain_name'] = id + '.' + domain
    cfg['metadata']['etcd_initial_cluster'] = etcd_init
    cfg['metadata']['etcd_name'] = id
    cfg['metadata']['ssh_authorized_keys'] = [ssh_key_local]
    cfg
  end

  def bk_node_cfg
    cfg = bk_node.dup
    etcd_endpoints = 'http://node1' + '.' + domain + ':2379'
    cfg['id'] = 'node' + @id
    cfg['selector']['mac'] = mac_addr
    cfg['metadata']['domain_name'] = 'node' + @id + '.' + domain
    cfg['metadata']['etcd_endpoints'] = etcd_endpoints
    cfg['metadata']['ssh_authorized_keys'] = [ssh_key_local]
    cfg
  end

  def bk_controller
    {"id"=>"node1",
     "name"=>"Controller Node",
     "profile"=>"bootkube-controller",
     "selector"=>{"mac"=>""},
     "metadata"=>
       {"domain_name"=>"",
        "etcd_initial_cluster"=>"node1=http://node1.example.com:2380",
        "etcd_name"=>"node1",
        "k8s_dns_service_ip"=>"10.3.0.10",
        "pxe"=>"true",
        "ssh_authorized_keys"=> [""]}}
  end

  def bk_node
    {"id"=>"node2",
     "name"=>"Worker Node",
     "profile"=>"bootkube-worker",
     "selector"=>{"mac"=>"52:54:00:b2:2f:86"},
     "metadata"=>
       {"domain_name"=>"node2.example.com",
        "etcd_endpoints"=>"node1.example.com:2379",
        "k8s_dns_service_ip"=>"10.3.0.10",
        "pxe"=>"true",
        "ssh_authorized_keys"=> [""]}}
  end

  def domain
    (Pushcfg::WORK_DIR + 'hostname').read.split('.')[1..-1].join('.').strip
  end

  def mac_addr
    addr = (Pathname.new('/proc/net/arp')).read.lines[1..-1].grep(/#{@ip}/i).first
    addr ? addr.split(" ")[3] : (raise ArgumentError, "mac address for #{@ip} not found!")
  end

  def ssh_key_local
    Pathname.new('~/.ssh/id_rsa.pub').expand_path.read
  end

end

class Pushcfg < Sinatra::Base
  include Cfg
  WORK_DIR = Pathname.new '/opt/bootkube'
  MATCHBOX_DIR = Pathname.new '/var/lib/matchbox'

  configure do
    disable :logging
    set port: 8790
    set bind: '0.0.0.0'
  end

  get '/boot' do
    @ip = @env['REMOTE_ADDR']
    install
    content_type 'text/plain'
    '#!ipxe' + "\n" + 'autoboot net1' + "\n"
  end

  get '/node' do
    @src_files = WORK_DIR + 'assets/auth/kubeconfig'
    respond
  end

  get '/controller' do
    @src_files = WORK_DIR + 'assets'
    respond
  end

  private
  def respond
    begin
      setvars
      run_cmd
    rescue
      puts 'could not install kubecfg to ' + @ip
    end
  end

  def setvars
    @ip = @env['REMOTE_ADDR']
    @method = strip(@env['REQUEST_PATH'])

    ssh_opt = '-oStrictHostKeyChecking=no'
    @scp = Cocaine::CommandLine.new("scp", ":opt -r :src :dst")
    @scp_command = {
                   opt: ssh_opt,
                   src: @src_files.expand_path.to_s,
                   dst: ('core@' + @ip + ':/home/core')
                   }

    @ssh = Cocaine::CommandLine.new("ssh", ":opt :dst :cmd")
    @ssh_command = {
                   opt: ssh_opt,
                   dst: ('core@' + @ip)
                   }

    volumes = %w(/home/core/.ssh/id_rsa:/root/.ssh/id_rsa:ro /home/core/.ssh/id_rsa.pub:/root/.ssh/id_rsa.pub:ro).join(' -v ')
    @docker = Cocaine::CommandLine.new("/usr/bin/docker", "-d --rm -ti -v #{volumes} ruby :cmd")
  end

  def run_cmd
    @docker.run(cmd: @scp.command(@scp_command))
    @docker.run(cmd: @ssh.command(@ssh_command.merge(cmd: cmd[@method.to_sym])))
    # puts @docker.command(cmd: @scp.command(@scp_command))
    # puts @docker.command(cmd: @ssh.command(@ssh_command.merge(cmd: cmd[@method.to_sym])))
  end

  def cmd
    {controller: 'sudo mkdir -p /opt/bootkube && sudo mv /home/core/assets /opt/bootkube/assets && sudo systemctl start bootkube',
     node: 'sudo mkdir -p /etc/kubernetes && sudo mv /home/core/kubeconfig /etc/kubernetes/kubeconfig'}
  end

  def strip slash
    slash.split('/').last
  end

  def arp
    #
  end
  run!
end
