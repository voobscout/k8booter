require 'sinatra'
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

  def respond
    begin
      setvar
      install_cfg
      send(strip(@method).to_sym)
    rescue
      puts 'could not install kubecfg to ' + @ip
    end
  end

  def install_cfg
    `scp -r #{@src_files.expand_path.to_s} core@#{@ip}:/home/core`
  end

  def controller
    `ssh core@#{@ip} 'sudo mkdir -p /opt/bootkube && sudo mv /home/core/assets /opt/bootkube/assets && sudo systemctl start bootkube'`
  end

  def node
    `ssh core@#{@ip} 'sudo mkdir -p /etc/kubernetes && sudo mv /home/core/kubeconfig /etc/kubernetes/kubeconfig'`
  end

  def strip slash
    slash.split('/').last
  end

  def setvar
    @ip = @env['REMOTE_ADDR']
    @method = @env['REQUEST_PATH']
  end

  run!
end
