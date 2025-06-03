# net.tcl – Lightweight Tcl TCP Client Library

`net.tcl` is a minimalist Tcl module for managing TCP client connections using non-blocking sockets. Built around Tcl's `socket` and `fileevent`, it provides a streamlined API for connecting, sending, and receiving data over TCP, ideal for modular systems or interprocess communication in VPN-secured environments.

## ✨ Features
- Simple TCP client interface using Tcl's native socket API
- Non-blocking I/O with `fileevent` callbacks
- Designed for modular systems (like Rivet-connected or daemon-based flows)
- No external dependencies
- Cleanly handles open/send/receive/close logic
- Suitable for intra-VPN communication

## 🔧 Basic Usage

```tcl
# Connect to a server
net::client::connect 127.0.0.1 9000 -command ::myHandler

# Send data
net::client::send "Hello from Tcl!"

# Close connection
net::client::close
```

## 🧱 Structure
- `net::client::connect`: Opens a socket and sets up callbacks
- `net::client::send`: Sends string data through the socket
- `net::client::close`: Terminates the connection gracefully

## 🛠️ Customization
You can pass a custom command to handle incoming data:
```tcl
proc ::myHandler {sock data} {
    puts "Received: $data"
}
```

## 📜 License
MIT (or your preferred open-source license)

## 🙏 Acknowledgements
Created to support lightweight interprocess communication in modular Tcl projects, including AeroAlebrije components.
