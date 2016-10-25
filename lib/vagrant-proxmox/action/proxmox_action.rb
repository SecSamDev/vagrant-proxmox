module VagrantPlugins
  module Proxmox
    module Action
      # This class provdes helper functions.
      class ProxmoxAction
        protected

        def next_action(env)
          @app.call env
        end

        def get_machine_ip_address(env)
          config = env[:machine].provider_config
          if config.vm_type == :qemu
            env[:machine].config.vm.networks.select \
              { |type, _| type == :forwarded_port }.first[1][:host_ip] || nil
          else
            env[:machine].config.vm.networks.select \
              { |type, _| type == :public_network }.first[1][:ip] || nil
          end
        end

        def get_machine_interface_name(env)
          env[:machine].config.vm.networks.select \
            { |type, _| type == :public_network }.first[1][:interface] || nil
        end

        def get_machine_bridge_name(env)
          env[:machine].config.vm.networks.select \
            { |type, _| type == :public_network }.first[1][:bridge] || nil
        end

        def get_machine_gw_ip(env)
          env[:machine].config.vm.networks.select \
            { |type, _| type == :public_network }.first[1][:gw] || nil
        end

        def get_machine_macaddress(env)
          env[:machine].config.vm.networks.select \
            { |type, _| type == :public_network }.first[1][:macaddress] || nil
        end

        def connection(env)
          env[:proxmox_connection]
        end
      end
    end
  end
end
