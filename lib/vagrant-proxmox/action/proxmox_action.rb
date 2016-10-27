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

        def get_rest_boolean(input_boolean)
          if input_boolean
            1
          else
            0
          end
        end

        # get lxc network config
        #
        # Format with right order:
        # name=<string>[,bridge=<bridge>][,firewall=<1|0>][,gw=<GatewayIPv4>]
        #   [,gw6=<GatewayIPv6>][,hwaddr=<XX:XX:XX:XX:XX:XX>]
        #   [,ip=<IPv4Format/CIDR>][,ip6=<IPv6Format/CIDR>][,mtu=<integer>]
        #   [,rate=<mbps>][,tag=<integer>][,trunks=<vlanid[;vlanid...]>]
        #   [,type=<veth>]
        def add_lxc_network_config(env, params)
          env[:machine].config.vm.networks.each do |n|
            # skip forwarded_port
            if n.first == :forwarded_port
              env[:ui].info I18n.t('vagrant_proxmox.network_setup_ignored',
                                   net_config: n)
              next
            end

            # c = network config hash
            c = n.last
            unless c.include?(:net_id)
              raise Errors::VMConfigError,
                    error_msg: "Network #{n} has no :net_id element."
            end

            # use interface name detection
            auto_interface = get_lxc_interface_name(c)
            c[:interface] = auto_interface if auto_interface

            unless c.include?(:interface)
              raise Errors::VMConfigError,
                    error_msg: "Network #{n} has no :interface element."\
                               " Set it to 'eth0' or similar."
            end

            unless c.include?(:bridge)
              raise Errors::VMConfigError,
                    error_msg: "Network #{n} has no :bridge element."\
                               ' You need a bridge to attach your interface to.'
            end

            # configuration entry
            cfg = []
            # name=<string>
            cfg.push("name=#{c[:interface]}")
            # [,bridge=<bridge>]
            %w(bridge firewall gw gw6 hwaddr).each do |entry|
              e = entry.to_sym
              cfg.push("#{entry}=#{c[e]}") if c.include?(e)
            end
            # IPv4 - primary ip protocol
            e = :ip
            if c[:type] == 'dhcp' || (c.include?(e) && c[e] == 'dhcp')
              cfg.push('ip=dhcp')
            else
              v = get_ip_cidr4(c)
              cfg.push("ip=#{v}") if v
            end
            # IPv6 - additionally used ip protocol
            e = :ip6
            if c.include?(e) && c[e] == 'dhcp'
              cfg.push('ip6=dhcp')
            else
              v = get_ip_cidr6(c)
              cfg.push("ip6=#{v}") if v
            end
            # other options
            %w(mtu rate tag trunks).each do |entry|
              e = entry.to_sym
              cfg.push("#{entry}=#{c[e]}") if c.include?(e)
            end
            # static interface type, similar in all cases
            cfg.push('type=veth')
            # give user feedback about network used setup
            env[:ui].detail I18n.t('vagrant_proxmox.network_setup_info',
                                 net_id: c[:net_id].to_s,
                                 net_config: cfg.join(','))
            params[c[:net_id].to_s] = cfg.join(',')
          end
        end

        # Get CIDR notation for IPv4 address
        # @param c network configuration part of \
        #          env[:machine].config.vm.networks
        # @param type type of ipaddress ip=IPv4, ip6=IPV6
        #
        # @return [String or Boolean]
        def get_ip_cidr(c, type)
          unless c.include?(:id)
            raise Errors::InternalPluginError, error_msg: \
              "Invalid network configuration part supplied: #{c}"
          end

          if type == 'ip'
            get_ip_cidr4(c)
          elsif type == 'ip6'
            get_ip_cidr6(c)
          else
            raise Errors::InvalidCidrTypeError, error_msg: type.to_s
          end
        end

        # Get CIDR notation for IPv4 address
        # @param c network configuration part of \
        #          env[:machine].config.vm.networks
        #
        # @return [String, Boolean]
        def get_ip_cidr4(c)
          return false unless c.include?(:ip)
          return false unless c.include?(:ip_cidr)
          "#{c[:ip]}/#{c[:ip_cidr]}"
        end

        # Get CIDR notation for IPv6 address
        # @param c network configuration part of \
        #          env[:machine].config.vm.networks
        #
        # @return [String, Boolean]
        def get_ip_cidr6(c)
          return false unless c.include?(:ip6)
          return false unless c.include?(:ip6_cidr)
          "#{c[:ip6]}/#{c[:ip6_cidr]}"
        end

        # Detect interface name from net_id
        # @param c network configuration part of \
        #          env[:machine].config.vm.networks
        #
        # @return [String or nil]
        def get_lxc_interface_name(c)
          # detect interface name
          return nil unless c.include?(:net_id)
          unless c.include?(:interface) == true
            netif_id = c[:net_id][/^net(\d+)$/, 1]
            # return nil if detection failed
            return nil if netif_id == c[:net_id]
            "eth#{netif_id}"
          end
        end

        # Add LXC mount points to params
        # Reads params and combines all defined lxc_mount_points to params.
        #
        # Format with right order:
        # mp[n]: [volume=]<volume>,mp=<Path>[,acl=<1|0>][,backup=<1|0>]
        #        [,quota=<1|0>][,ro=<1|0>][,size=<DiskSize>]
        #
        def add_lxc_mount_points(env, config, params)
          config.lxc_mount_points.each do |mp, cfg|
            # merge with defaults
            c = config.lxc_mount_point_defaults.merge(cfg)
            # validate config
            unless mp =~ /^mp\d$/
              raise Errors::VMConfigError,
                    error_msg: "Invalid mount point #{mp} in config."
            end
            # check required options
            %i(volume mp backup size).each do |k|
              unless c.include?(k)
                raise Errors::VMConfigError,
                      error_msg: "MountPoint #{mp} must have a '#{k}' item"
              end
            end
            # combine volume:size into volume
            c[:volume] = "#{c[:volume]}:#{c[:size]}"
            # translate booleans
            %i(acl backup quota ro).each do |k|
              c[k] = get_rest_boolean(c[k])
            end
            # build config string
            cs = []
            %i(volume mp acl backup quota ro).each do |k|
              cs.push("#{k}=#{c[k]}")
            end
            # put mount point back into params
            e = mp.to_sym
            params[e] = cs.join(',')
            env[:ui].detail("MountPoint #{mp}: #{params[e]}")
          end
        end
      end
    end
  end
end
