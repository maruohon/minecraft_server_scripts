# -*- coding: UTF-8 -*-

import socket
import sys


timeout = 1.7
server_host = "localhost"
server_port = 25565

# Minecraft Ping protocol to use:
# 1 = Minecraft Beta 1.8 - Minecraft 1.3
# 2 = Minecraft 1.4 - 1.5
# 3 = Minecraft 1.6
protocol = 1

# Parse the command line arguments
# We can have '[host]', '[host] [port]', '[host:port]',
# '[host] [port] [timeout]' or '[host:port] [timeout]'
if len(sys.argv) == 2:
	if ':' in sys.argv[1]:
		tmp = str(sys.argv[1]).split(':')
		server_host = str(tmp[0])
		server_port = int(tmp[1])
	else:
		server_host = str(sys.argv[1])

elif len(sys.argv) >= 3:
	if ':' in sys.argv[1]:
		tmp = str(sys.argv[1]).split(':')
		server_host = str(tmp[0])
		server_port = int(tmp[1])
		timeout = float(sys.argv[2])
	else:
		server_host = str(sys.argv[1])
		server_port = int(sys.argv[2])

	if len(sys.argv) >= 4:
		timeout = float(sys.argv[3])
		if len(sys.argv) >= 5:
			protocol = int(sys.argv[4])


#print str('host: {} port: {} timeout: {}').format(server_host, server_port, timeout)
#sys.exit()

def ping(host, port, timeout = 1.7, protocol = 1):
	"""Ping the server and return the values the server gives us"""

	if protocol == 1:
		# Send 0xFE: Server list ping (Minecraft Beta 1.8 - 1.3)
		msg = "\xFE"
		#sock.sendall("\xFE")
	elif protocol == 2:
		# Send 0xFE 0x01: Server list ping (Minecraft 1.4 - 1.5)
		msg = "\xFE\x01"
		#sock.sendall("\xFE\x01")
	elif protocol == 3:
		# Server list ping (Minecraft 1.6)
		msg = "\xFE\x01\xFA"
		msg += "\x00\x0B" # The length of the following string, in characters, as a short (always 11)

		# "MC|PingHost" encoded as a big-endian UCS-2 string:
		msg += "\x00\x4D\x00\x43\x00\x7C\x00\x50\x00\x69\x00\x6E\x00\x67\x00\x48\x00\x6F\x00\x73\x00\x74"

		# FIXME/TODO:
		# Alternatively:
		#msg += str('MC|PingHost').encode('UTF-16BE')

		#msg += "" # The length of the rest of the data, as a short. Compute as 7 + 2 * strlen(hostname)
		#msg += "" # Protocol version, currently 74 (decimal)
		#msg += "" # The length of following string, in characters, as a short
		#msg += "" # The hostname the client is connecting to, encoded in the same way as "MC|PingHost"
		#msg += "" # The port the client is connecting to, as an int
	else:
		print(str('ping(): Error, invalid protocol: {}').format(protocol))
		return None

	try:
		#sock = socket.create_connection((server_address, server_port), timeout)
		sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	except socket.error as msg:
		#print('socket(): except:', msg)
		sock = None
		return None

	try:
		#sock.setblocking(0)
		sock.settimeout(timeout)
		sock.connect((host, port))
	except socket.error as msg:
		#print('connect(): except:', msg)
		sock = None
		return None

	sock.sendall(msg)

	try:
		val = sock.recv(256)
	except socket.error as msg:
		sock.close()
		#print('recv(): except:', msg)
		return None

	sock.shutdown(socket.SHUT_RDWR)
	sock.close()

	# Check for a valid 0xFF disconnect
	if val[0] != "\xFF":
		return None

	if protocol == 1:
		# Remove the packet ident (0xFF) and the short containing the length of the string
		# Minecraft Beta 1.8 - 1.3
		val = val[3:]
	elif protocol == 2 or protocol == 3:
		# Remove the packet ident (0xFF) and the short containing the length of the string
		# and the rest of the crap
		# Minecraft 1.4 - 1.5, 1.6
		val = val[9:]

	# Decode UCS-2 string
	#val = val.decode('UTF-16LE')
	val = val.decode('UTF-16BE')

	if protocol == 1:
		# Split into a list (Minecraft Beta 1.8 - 1.3)
		val = val.split(u"\xA7")
	elif protocol == 2 or protocol == 3:
		# Split into a list (Minecraft 1.4 - 1.5, 1.6)
		val = val.split("\x00")

	# Debug:
	#print('Length of val:', len(val))
	#print(val)
	#return "foo"

	#if len(val) < 3:
	#	return None

	if len(val) == 3:
		# Return a dictionary of values (Minecraft Beta 1.8 - 1.3)
		# values: MOTD, num_player, max_players
		return {'motd': val[0],\
			'num_players': int(val[1]),\
			'max_players': int(val[2])}
	elif len(val) == 5:
		# Return a dictionary of values (Minecraft 1.4 - 1.5, 1.6)
		# values: protocol_version, version, MOTD, num_player, max_players
		return {'protocol_version': int(val[0]),\
			'version': val[1],\
			'motd': val[2],\
			'num_players': int(val[3]),\
			'max_players': int(val[4])}
	else:
		return None





def check_server(host, port, timeout = 1.7, protocol = 1):
	"""Check if the server is up by ping()ing it checking for the known keys"""

	data = ping(host, port, timeout, protocol)
	#print('host:', host, 'port:', port, data)

	if type(data) is dict:
		if 'version' in data:
			msg = str('{}:{} ([{}], {}): OK').format(host, port, data['version'], data['motd'])
			print msg			
		elif 'motd' in data:
			msg = str('{}:{} ({}): OK').format(host, port, data['motd'])
			print msg
			#print '%s: up' % data['motd']
		else:
			msg = str('{}:{}: N/A').format(host, port)
			print msg
			#print '%s: down' % data['motd']
	else:
		msg = str('{}:{}: N/A').format(host, port)
		print msg

	return None


check_server(server_host, server_port, timeout, protocol)

