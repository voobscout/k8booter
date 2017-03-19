require 'sinatra'
require 'cocaine'
require 'pathname'

class Pushcfg < Sinatra::Base
  WORK_DIR = Pathname.new '/opt/bootkube'

  configure do
    disable :logging
    set port: 8790
    set bind: '0.0.0.0'
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

  run!
end
