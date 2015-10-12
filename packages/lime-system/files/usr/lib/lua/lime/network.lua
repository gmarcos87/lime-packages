#!/usr/bin/lua

network = {}

local bit = require("bit")
local ip = require("luci.ip")
local libuci = require("uci")
local fs = require("nixio.fs")

local config = require("lime.config")
local utils = require("lime.utils")

network.limeIfNamePrefix="lm_net_"
network.protoParamsSeparator=":"
network.protoVlanSeparator="_"


function network.get_mac(ifname)
	local path = "/sys/class/net/"..ifname.."/address"
	local mac = assert(fs.readfile(path), "network.get_mac(...) failed reading: "..path):gsub("\n","")
	return utils.split(mac, ":")
end

function network.primary_interface()
	return config.get("network", "primary_interface")
end

function network.primary_mac()
	return network.get_mac(network.primary_interface())
end

function network.generate_host(ipprefix, hexsuffix)
    -- use only the 8 rightmost nibbles for IPv4, or 32 nibbles for IPv6
    hexsuffix = hexsuffix:sub((ipprefix[1] == 4) and -8 or -32)

    -- convert hexsuffix into a cidr instance, using same prefix and family of ipprefix
    local ipsuffix = ip.Hex(hexsuffix, ipprefix:prefix(), ipprefix[1])

    local ipaddress = ipprefix
    -- if it's a network prefix, fill in host bits with ipsuffix
    if ipprefix:equal(ipprefix:network()) then
        for i in ipairs(ipprefix[2]) do
            -- reset ipsuffix netmask bits to 0
            ipsuffix[2][i] = bit.bxor(ipsuffix[2][i],ipsuffix:network()[2][i])
            -- fill in ipaddress host part, with ipsuffix bits
            ipaddress[2][i] = bit.bor(ipaddress[2][i],ipsuffix[2][i])
        end
    end

    return ipaddress
end

function network.primary_address(offset)
    local offset = offset or 0
    local pm = network.primary_mac()
    local ipv4_template = config.get("network", "main_ipv4_address")
    local ipv6_template = config.get("network", "main_ipv6_address")

    local ipv4_maskbits = ipv4_template:match("[^/]+/(%d+)")
    ipv4_template = ipv4_template:gsub("/%d-/","/")
    local ipv6_maskbits = ipv6_template:match("[^/]+/(%d+)")
    ipv6_template = ipv6_template:gsub("/%d-/","/")

    ipv4_template = utils.applyMacTemplate10(ipv4_template, pm)
    ipv6_template = utils.applyMacTemplate16(ipv6_template, pm)

    ipv4_template = utils.applyNetTemplate10(ipv4_template)
    ipv6_template = utils.applyNetTemplate16(ipv6_template)

    local m4, m5, m6 = tonumber(pm[4], 16), tonumber(pm[5], 16), tonumber(pm[6], 16)
    local hexsuffix = utils.hex((m4 * 256*256 + m5 * 256 + m6) + offset)
    ipv4_template = network.generate_host(ip.IPv4(ipv4_template), hexsuffix)
    ipv6_template = network.generate_host(ip.IPv6(ipv6_template), hexsuffix)

    ipv4_template[3] = tonumber(ipv4_maskbits)
    ipv6_template[3] = tonumber(ipv6_maskbits)
    
    return ipv4_template, ipv6_template
end

function network.setup_rp_filter()
	local sysctl_file_path = "/etc/sysctl.conf";
	local sysctl_options = "";
	local sysctl_file = io.open(sysctl_file_path, "r");
	while sysctl_file:read(0) do
		local sysctl_line = sysctl_file:read();
		if not string.find(sysctl_line, ".rp_filter") then sysctl_options = sysctl_options .. sysctl_line .. "\n" end 
	end
	sysctl_file:close()
	
	sysctl_options = sysctl_options .. "net.ipv4.conf.default.rp_filter=2\nnet.ipv4.conf.all.rp_filter=2\n";
	sysctl_file = io.open(sysctl_file_path, "w");
	sysctl_file:write(sysctl_options);
	sysctl_file:close();
end

function network.setup_dns()
	local content = {}
	for _,server in pairs(config.get("network", "resolvers")) do
		table.insert(content, server)
	end
	local uci = libuci:cursor()
	uci:foreach("dhcp", "dnsmasq", function(s) uci:set("dhcp", s[".name"], "server", content) end)
	uci:save("dhcp")
	fs.writefile("/etc/dnsmasq.conf", "conf-dir=/etc/dnsmasq.d\n")
	fs.mkdir("/etc/dnsmasq.d")
end

function network.clean()
	print("Clearing network config...")

	local uci = libuci:cursor()

	uci:delete("network", "globals", "ula_prefix")
	uci:set("network", "wan", "proto", "none")
	uci:set("network", "wan6", "proto", "none")

	--! Delete interfaces and devices generated by LiMe
	uci:foreach("network", "interface", function(s) if utils.stringStarts( s[".name"], network.limeIfNamePrefix ) then uci:delete("network", s[".name"]) end end)
	uci:foreach("network", "device", function(s) if utils.stringStarts( s[".name"], network.limeIfNamePrefix ) then uci:delete("network", s[".name"]) end end)
	uci:save("network")

	print("Disabling odhcpd")
	io.popen("/etc/init.d/odhcpd disable || true"):close()

	print("Cleaning dnsmasq")
	uci:foreach("dhcp", "dnsmasq", function(s) uci:delete("dhcp", s[".name"], "server") end)
	uci:save("dhcp")

	print("Disabling 6relayd...")
	fs.writefile("/etc/config/6relayd", "")
end

function network.scandevices()
	local devices = {}
	local switch_vlan = {}

	function dev_parser(dev)
		if dev:match("^eth%d+$") then
			devices[dev] = devices[dev] or {}
		end

		if dev:match("^eth%d+%.%d+$") then
			local rawif = dev:match("^eth%d+")
			devices[rawif] = { nobridge = true }
			devices[dev] = {}
		end

		if dev:match("^wlan%d+_%w+$") then
			devices[dev] = {}
		end
	end

	function owrt_ifname_parser(section)
		local ifn = section["ifname"]
		if ( type(ifn) == "string" ) then dev_parser(ifn) end
		if ( type(ifn) == "table" ) then for _,v in pairs(ifn) do dev_parser(v) end end
	end

	function owrt_device_parser(section)
		dev_parser(section["name"])
		dev_parser(section["ifname"])
	end

	function owrt_switch_vlan_parser(section)
		local kernel_visible = section["ports"]:match("0t")
		if kernel_visible then switch_vlan[section["vlan"]] = section["device"] end
	end

	--! Scrape from uci wireless
	local uci = libuci:cursor()
	uci:foreach("wireless", "wifi-iface", owrt_ifname_parser)

	--! Scrape from uci network
	uci:foreach("network", "interface", owrt_ifname_parser)
	uci:foreach("network", "device", owrt_device_parser)
	uci:foreach("network", "switch_vlan", owrt_switch_vlan_parser)

	--! Scrape plain ethernet devices from /sys/class/net/
	local stdOut = io.popen("ls -1 /sys/class/net/ | grep -x 'eth[0-9][0-9]*'")
	for dev in stdOut:lines() do dev_parser(dev) end
	stdOut:close()

	--! Scrape switch_vlan devices from /sys/class/net/
	local stdOut = io.popen("ls -1 /sys/class/net/ | grep -x 'eth[0-9][0-9]*\.[0-9][0-9]*'")
	for dev in stdOut:lines() do if switch_vlan[dev:match("%d+$")] then dev_parser(dev) end end
	stdOut:close()

	return devices
end

function network.configure()
	local specificIfaces = {}
	config.foreach("net", function(iface) specificIfaces[iface["linux_name"]] = iface end)
	local fisDevs = network.scandevices()

	network.setup_rp_filter()

	network.setup_dns()

	local generalProtocols = config.get("network", "protocols")
	for _,protocol in pairs(generalProtocols) do
		local protoModule = "lime.proto."..utils.split(protocol,":")[1]
		if utils.isModuleAvailable(protoModule) then
			local proto = require(protoModule)
			xpcall(function() proto.configure(utils.split(protocol, network.protoParamsSeparator)) end,
			       function(errmsg) print(errmsg) ; print(debug.traceback()) end)
		end
	end

	--! For each scanned fisical device, if there is a specific config apply that one otherwise apply general config
	for device,flags in pairs(fisDevs) do
		local owrtIf = specificIfaces[device]
		local deviceProtos = generalProtocols
		if owrtIf then deviceProtos = owrtIf["protocols"] end

		for _,protoParams in pairs(deviceProtos) do
			local args = utils.split(protoParams, network.protoParamsSeparator)
			if args[1] == "manual" then break end -- If manual is specified do not configure interface
			local protoModule = "lime.proto."..args[1]
			for k,v in pairs(flags) do args[k] = v end
			if utils.isModuleAvailable(protoModule) then
				local proto = require(protoModule)
				xpcall(function() proto.configure(args) ; proto.setup_interface(device, args) end,
				       function(errmsg) print(errmsg) ; print(debug.traceback()) end)
			end
		end
	end
end

function network.createVlanIface(linuxBaseIfname, vid, openwrtNameSuffix, vlanProtocol)

	vlanProtocol = vlanProtocol or "8021ad"
	openwrtNameSuffix = openwrtNameSuffix or ""

	local owrtDeviceName = network.limeIfNamePrefix..linuxBaseIfname..openwrtNameSuffix.."_dev"
	local owrtInterfaceName = network.limeIfNamePrefix..linuxBaseIfname..openwrtNameSuffix.."_if"
	owrtDeviceName = owrtDeviceName:gsub("[^%w_]", "_") -- sanitize uci section name
	owrtInterfaceName = owrtInterfaceName:gsub("[^%w_]", "_") -- sanitize uci section name

	local vlanId = vid
	--! Do not use . as separator as this will make netifd create an 802.1q interface anyway
	--! and sanitize linuxBaseIfName because it can contain dots as well (i.e. switch ports)
	local linux802adIfName = linuxBaseIfname:gsub("[^%w_]", "_")..network.protoVlanSeparator..vlanId
	local ifname = linuxBaseIfname
	if utils.stringStarts(linuxBaseIfname, "wlan") then ifname = "@"..network.limeIfNamePrefix..linuxBaseIfname end

	local uci = libuci:cursor()

	uci:set("network", owrtDeviceName, "device")
	uci:set("network", owrtDeviceName, "type", vlanProtocol)
	uci:set("network", owrtDeviceName, "name", linux802adIfName)
	uci:set("network", owrtDeviceName, "ifname", ifname)
	uci:set("network", owrtDeviceName, "vid", vlanId)

	uci:set("network", owrtInterfaceName, "interface")
	uci:set("network", owrtInterfaceName, "ifname", linux802adIfName)
	uci:set("network", owrtInterfaceName, "proto", "none")
	uci:set("network", owrtInterfaceName, "auto", "1")

	uci:save("network")

	return owrtInterfaceName, linux802adIfName, owrtDeviceName
end

return network
