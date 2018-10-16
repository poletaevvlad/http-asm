# http-asm

Very simple HTTP server written in x86_64 assembly for Linux.

This project provides a single-threaded implementation of the subset of HTTP 1.0 protocol. It is written in assembly language ([NASM](https://www.nasm.us/)) and has zero dependencies. All communications with outside world is performed exclusively via Linux system calls.

This project was written for fun and to further my understanding of assembly language and Linux OS. I cannot guarantee that this program is performant, secure, stable, working on your version of Linux, or compliant with the HTTP specs. Therefore it should not be used in production.

## Capabilities and limitations

http-asm server can:

- serve files by its URL
- display directory listings
- display errors (currently, only status codes 400, 403, 404 and 405 are supported)
- correctly handle non-ASCII characters and spaces in file name (url decoding)

Limitations of the current version include:

- default files are not supported (e.g. `index.html`)
- http-asm does not attempt to determine a mime-type of a file (no `Content-Type` header is provided. The user agent is allowed by the protocol specification to guess mime-type.)
- keep-alive connections are not supported
- all requests are processed sequentially

I do not know if there will be any further development of this project.


## Building

To build this project execute the following:

```bash
git clone https://github.com/poletaevvlad/http-asm.git
cd http-asm
make
```

## Usage

In order to run http-asm server the following syntax must be used:

```bash
http-asm <PORT> <PATH>
```

Where `<PORT>` is a valid TCP/IP port number and `<PATH>` is a path to the document root.
