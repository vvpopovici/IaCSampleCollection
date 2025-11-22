#!/usr/local/bin/python

import socket;
import os;
from datetime import datetime;
import urllib.request

socket.setdefaulttimeout(5)

header_log = '<br>----------<br>\n'

print("# Getting start date and time")
log = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
print(log)
header_log +=f'Started at: {log}<br>\n'

print(f"# Getting Env Var APP_VERSION")
log = os.getenv('APP_VERSION', 'unknown')
print(log)
header_log +=f'APP_VERSION: {log}<br>\n'

print("# Getting localhost name and private IP")
log = f'Hostname={socket.gethostname()}, Private IP={socket.gethostbyname(socket.gethostname())}'
print(log)
header_log +=f'Localhost info: {log}<br>\n'

print("# Getting public IP from ifconfig.me")
try:
  response = urllib.request.urlopen('http://ifconfig.me/ip', timeout=5)
  log = response.read().decode().strip()
except Exception as e:
  log = f'Unavailable ({e})'
print(log)
header_log +=f'Public IP: {log}<br>\n'

#=====
import http.server
import socketserver
import sys

class DynamicIndexHandler(http.server.SimpleHTTPRequestHandler):
  def do_GET(self):
    if self.path == "/" or self.path == "/index.html":
      # Generate dynamic content
      full_log = header_log
      full_log += '<br>==========<br>\n'

      print("# Getting refresh time")
      log = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
      print(log)
      full_log += f'Refreshed at {log}<br>\n'

      print("# Write to index.html")
      with open('./index.html', 'w') as output_file:
        output_file.writelines(full_log)

      print("# Serve the index.html as usual")
      return super().do_GET()

try:
  PORT = int(sys.argv[1])
except:
  try:
    PORT = int(os.environ['PORT'])
  except:
    PORT = 5000

handler = DynamicIndexHandler

with socketserver.TCPServer(('', PORT), handler) as httpd:
  print(f'# Serving at port {PORT}')
  httpd.serve_forever()
