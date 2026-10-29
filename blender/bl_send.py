# Sends a Python file to the BlenderMCP add-on (port 9876) and prints the result.
# Usage: python3 bl_send.py script.py
import json, socket, sys

code = open(sys.argv[1]).read()
s = socket.create_connection(("localhost", 9876), timeout=600)
s.sendall(json.dumps({"type": "execute_code", "params": {"code": code}}).encode())
buf = b""
while True:
    chunk = s.recv(65536)
    if not chunk:
        break
    buf += chunk
    try:
        res = json.loads(buf)
        break
    except json.JSONDecodeError:
        pass
print(json.dumps(res, indent=1)[:4000])
