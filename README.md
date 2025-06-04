# net.tcl – Lightweight Tcl TCP Client Library

`net.tcl` is a minimalist Tcl module for managing TCP client connections using non-blocking sockets. Built around Tcl's `socket` and `fileevent`, it provides a streamlined API for connecting, sending, and receiving data over TCP, ideal for modular systems or interprocess communication in VPN-secured environments.

## ✨ Features
- Simple TCP client interface using Tcl's native socket API
- Returns a dedicated namespace as handler for each connection
- Non-blocking I/O using `fileevent` internally
- Designed for modular systems (like Rivet-connected or daemon-based flows)
- No external dependencies
- Cleanly handles open/send/receive/close logic
- Suitable for intra-VPN communication

## 🔧 Basic Usage

```tcl
# Connect to a server, receive a handler namespace
set conn [net::client::connect 127.0.0.1 9000]

# Send data through the connection
$conn send "Hello from Tcl!"

# Close the connection
$conn close
```

## 🧱 Structure
- `net::client::connect`: Opens a socket and returns a handler namespace
- `$handler send`: Sends string data over the socket
- `$handler close`: Closes the connection cleanly

## 🛠️ Customization
Handlers can be renamed for clarity:

```tcl
set conn [net::client::connect 127.0.0.1 9000]
rename $conn ::handler
::handler send "Using a renamed handler"
```

## 📜 License
MIT (or your preferred open-source license)

## 🙏 Acknowledgements
Created to support lightweight interprocess communication in modular Tcl projects.
