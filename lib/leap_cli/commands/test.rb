module LeapCli; module Commands

  desc 'Run tests'
  command :test do |c|
    c.desc 'Creates files needed to run tests'
    c.command :init do |c|
      c.action do |global_options,options,args|
        generate_test_client_cert
        generate_test_client_openvpn_config
      end
    end

    c.desc 'Run tests'
    c.command :run do |c|
      c.action do |global_options,options,args|
        nodes = manager.filter!(args)
        if nodes.size > 1
          say "Testing these nodes: #{nodes.keys.join(', ')}"
          unless agree "Continue? "
            quit! "OK. Bye."
          end
        end

        nodes.keys.sort.each do |node_name|
          nodes[node_name].services.each do |service|
            config = "hiera/#{node_name}.yaml"
            system "rake -f #{Path.provider_base + "/Rakefile"} test SERVICE=#{service} CONFIG=#{config}"
          end
        end
      end
    end

    c.default_command :run
  end

  private

  def generate_test_client_openvpn_config
    template = read_file! Path.find_file(:test_client_openvpn_template)

    ['production', 'testing', 'local'].each do |tag|
      vpn_nodes = manager.nodes[:tags => tag][:services => 'openvpn']
      if vpn_nodes.any?
        config = Util.erb_eval(template, binding)
        write_file! ('test_openvpn_'+tag).to_sym, config
      end
    end
  end

end; end
