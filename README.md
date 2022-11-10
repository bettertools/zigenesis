# Zigenesis

Build ANY project in ANY Language with Zig.

This repository aims to provide the code necessary to build any project written in any source language from a single binary dependency, the "Zig toolchain".  The Zig toolchain was chosen for this because:

- it is a single archive that can be downloaded/installed without having to install any other dependencies
- it supports cross-compilation without having to install extra pieces for each target
- it can build static binaries out of the box
- it is the smallest toolchain that supports these features
- it has a path to bootstrap from C (for obscure platforms that only provide a C compiler)
- it includes a build system

Once a project can be built with Zig, it also means that project can be built for any target supported by Zig.

This project should either provide fundamental build tool implementations, or, the glue needed for Zig to build any other tool/toolchain that would be necssary to build ANY project.  As an example, many projects use Makefiles that require the "make" tool.  This project must either provide an implementation of Make, or the code necessary to download and build Make from source with an external project like GNU Make.  In that case, the GNU Make project has its own set of dependencies to build it.  At least some of those dependencies will in turn also probably rely on Make which results in a dependency loop.  We'll need to break this loop by providing our own implementation of certain tools.

The decision to create our own implementation of a tool will depend on:

- how generally useful is the tool?
- how simple is the tool to implement?
- how easy is it to build an external implementation from source and how many targets can it support?

# Test Case

I should be able to create a linux distribution that only has the Zig toolchain, this repository and a network connection and be able to build any project from source (without having to download any prebuilt binaries).

# TODO:
- maybe a BASH implementation in Zig?
    - BASH is used everywhere and I'm not sure how many platforms the GNU BASH
      implementation supports, so, it may be worth it to implement our own to
      support as many platforms as possible.
- more compressed archive formats (i.e. `.bz1`, `.xz`)
- better SSL support in iguana
- enhance the tar tool (it may not support some of the variants in the wild)
