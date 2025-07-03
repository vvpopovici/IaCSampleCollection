#!/usr/local/bin/python

import socket;
import os;
from datetime import datetime;

full_log = '<br>----------<br>\n'
socket.setdefaulttimeout(5);

print("### Getting current date and time")
log = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
print(log); full_log = full_log + log + '<br>\n';

print("### Getting localhost name and private IP")
name = socket.gethostname();
ip = socket.gethostbyname(name);
log = f'Hostname={name}, Private IP={ip}'
print(log); full_log = full_log + log + '<br>\n';

print("### Getting public IP from ifconfig.me")
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
sock.connect(('ifconfig.me', 80));
sock.send(b'GET / HTTP/1.1\r\nHost:ifconfig.me\r\nConnection: close\r\n\r\n');
response = sock.recv(4096);
sock.close();
log = f'Public IP={[response.split()[i] for i in (0, 1, 2, -1)]}'
print(log); full_log = full_log + log + '<br>\n';

print("### Writing all to ./index.html")
output_file = open('./index.html', 'a');
output_file.writelines(full_log);
output_file.close();

output_file = open('./index.html', 'r');
print(output_file.read());
output_file.close();

#=====
import http.server
import socketserver
import sys

try:
  PORT = int(sys.argv[1])
except:
  try:
    PORT = int(os.environ['PORT'])
  except:
    PORT = 5000

handler = http.server.SimpleHTTPRequestHandler

with socketserver.TCPServer(('', PORT), handler) as httpd:
  print(f'### Serving at port {PORT}')
  httpd.serve_forever()
