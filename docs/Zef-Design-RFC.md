# Overview

This document tries to present my thinking on the principles behind the Zef
build system. It's not intended as a comprehensive document and is subject to
frequent changes, as I rethink some ideas and arrive at better alternatives. It
as well serves as a way for me to document these things in writing which often helps
me clarify some fuzzy ideas in my mind.

Note (21-04-2015): This is the old RFC, many design decisions have been made
since then and it does not reflect the current state.

# Preamble

Today we have a lot of ways to automate the building of our software. Each of
these is built with slightly different goals in mind and serves slightly
different purposes than the next one.

Currently I am starting a bigger project, and so I came to think about what kind
of build system I want to use. I arrived at a conclusion that I don't
particularly like any of them. Some of these I have tried only once, and some
others have earned my animosity because I had to fight with them in the past.
Learning from these experiences, I feel I can design a system that will work
better, be more flexible, more portable and faster, and generally not get in the
way of developers.

# Quick overview of existing build systems

The general consensus on [this StackOverflow question][1] is that "there are
many build systems, and they all suck". This is a sharp statement, and the
question is about C++ build systems, so I don't think it applies generally, but
I do think there is a lot of room for improvement. So, let's take a look at
the more prominent build systems.

[1]: https://stackoverflow.com/questions/12017580/c-build-systems-what-to-use

## make (vanilla)

Make is a very good build automation tool. However, by itself, it cannot be used
for more complex projects. I really like the design of make, the syntax of
Makefiles and its performance. But since it was designed with different goals in
mind, we cannot use make for projects that, for example, need to be configured
with different options. What if we want to exclude a certain feature from the
build, or build a version suitable for debugging? Since make is not aware of
these options, we must resort to adding a new step which generates Makefiles.

## autotools

GNU autotools (together with GNU make comprising the GNU Build System) are an
answer to this. You write some scripts that describe options, your desired
environment, etc., and you get a configure shell script which, when called,
creates Makefiles for you. You run ``make`` and voila, your project is built.
But here are some things I don't like:

* They have a lot of quirks that makes them hard to master. In my opinion, some
  things can be solved a lot more cleanly than they currently are.

* They are very tightly coupled to Unix systems. Windows users wishing to build
  the project need, at a minimum, a shell and a copy of make. This is not very
  pleasant, and, adding insult to injury, libtool and pkg-config are not very
  good at dealing with Windows libraries (this is understandable since Windows
  lacks a package system which would make it easy to version and locate
  libraries).

* If the configuration step fails for some reason, you must re-run it again from
  the beginning after fixing the problem. This is amplified by it being very
  slow due to the next point.
  
* The configuration step typically does a lot of costly fork's and exec's, with
  writing to disk, in order to test different features of the C compiler, for
  example. For me, I feel this is a bit of overkill. You should be able say 'my
  project builds on GCC, Clang, MSVC++ on a standard Linux, Windows 7 or later,
  and OS X platform', and be able to discard other compilers if you wish to.
  Automake checks if the C compiler is sane to such depths that no commonly used
  C compiler would violate.

## CMake

CMake is a cross-platform Makefile (and others) generator, so it gains a lot by
being able to create, for instance, Ninja makefiles or Microsoft Visual C++
project files. However, that flexibility fades as soon as you want to, for
example, tell the C++ compiler to set you up with a C++11 environment. You have
to specify the compiler flags, and different compilers use different ways to
specify this (I'm looking at you, MSVC++), so you lose this. If you want to copy
some files from the source directory to the build directory, you need to use
``cmake -E``, and this goes for any platform-specific function. This is awkward
at best.

Because there is no centralized place to find CMake modules, I've ended up
scooping them from different projects. I have counted 3 different
implementations for ``FindGTK2.cmake``, each from a different project where it
needed to be rewritten. PkgConfig support kind of solves this, but is a no-go
for Windows where it's very hard to get to work nice.

The syntax is also very strange. It's not a known programming language but is
Turing-complete (AFAIK), and you need to end if statements by duplicating the
condition from the beginning. Great for verbosity but bad for common sense.

## SCons

Now we're talking. SCons is Python-based and works quite well, from what I've
heard (I haven't really used it beyond for a test drive). Many reports on the
Internet say that it is slow because it's written in Python (is it?), and I
haven't been able to find a simple way of solving the problem with non-portable
compiler flags.

Keeping this section short because I don't have enough experience with it. It'd
be unfair to criticize something I haven't used enough.

## Conclusion

I've skimmed some of the existing ones, but only a few. I think there may be
more of these, even better ones, maybe some that would suit me completely. But
why not reinvent the wheel and have some fun while doing it? I'm not attempting
to completely justify my writing of a completely new build system. I just want
to point out that I have some experience with existing ones, and that I don't
quite like it.

# Goals

## General 

These are some general, more philosophical than technical goals.

### Modularity

Small modules, nothing homogenous. You should be able to plug in your own
modules and additions to Zef to customize your build process completely, and you
should be able to find modules, versioned, on some kind of central repository,
which suits your needs. As such, Zef will be implemented as a small core that
provides a platform for extensions, and the majority of the functionality will
be defined by modules.

### Speed

Constructing a DAG of dependencies and topologically sorting it, then running
the build process in order, is not a very expensive operation. As such, I don't
want it to take much time and be unnecessarily slow. So its core will be written
in a fast programming language. I name Rust as the language of choice here,
because I simply love it and would love to brush up on my skills of it.

### Succinctness

The files describing the build process shouldn't be tedious to write. They don't
have to be obvious to someone who doesn't understand Zef even minimally.
Makefiles have this quality, and I think it is very good. Conveying ideas in a
minimal form helps everyone except the people who are lazy and want free lunch.
See [this essay by Paul Graham][2] for some philosophy behind this.

[2]: http://www.paulgraham.com/power.html

### Simplicity

"Simplicity is the ultimate sophistication." - William Gaddis

Much like [The Arch Way][3], I aim for Zef to be as simple as possible,
achieving "complexity without complication", and be clear to others as well as to
me. Much of this is achieved by it being modular, but even the core features
should be consolidated in a few key principles from which all others should
follow. This is not an easy goal to achieve, and I think that's the one that I
need the community help for the most.

[3]: https://wiki.archlinux.org/index.php/The_Arch_Way

## Technical

A goal of Zef is to be everything a person needs to build a piece of software.
It should, of course, support fast incremental builds, out-of-tree builds,
automatically downloading and optionally compiling dependencies, scripting the
build process and configurability. Each Zef project can be described with its
name, version, optional info such as description, contributors, license etc.,
documented and clear options needed for its configuration, and some files that
describe how to arrive at the targets (final executable, tests, installation
etc.) via intermediate steps. It should also make no distinctions between the
configure and build steps; everything should be traced from the final leaf node
to the state where the build tree is empty. I think that this split makes no
sense unless the build tool is a makefile or project file generator, which is
not the case here.

# Core concepts

## Scriptability via Lua

Lua is a fast language, especially with LuaJIT (at least [one document][4]
suggest this), it is dynamically-typed, suitable for prototyping, and has
first-class functions. It is also reasonably succinct, and extensible. In 
my book, this is all that it takes for a language to be suitable for scripting
in a build system. Except the core, written in Rust, everything else in Zef will
be implemented in Lua.

[4]: https://github.com/logicchains/LPATHBench/blob/master/writeup.md

## Features and feature providers

A *feature* in Zef is simply an entity providing some functionality. For example,
a C compiler, a parser generator, or a linter are all features. It is directly
represented in Lua as a table that sits as a member of the ``zef`` namespace.
Zef targets can require some features as dependencies, and then use their
functionality in order to do something needed for them. Feature is an abstract
concept; an interface, if you will. However, there is no formal specification of
a single feature, it is identified only by its name. Since Lua uses duck typing,
anyone can implement a feature with their own interface, but it is in the
interest of all users that this is consistent. Such a thing may be ensured by
writing informal descriptions or providing a reference implementation for a
particular feature.

A *feature provider* in Zef is an implementor of a certain feature. It is
perfectly reasonable to have many providers for a feature such as "C compiler".
One of these may implement the feature as GCC, and the other one as MSVC. The
point is that the differences between these are abstracted away. This gives us
an extremely powerful mechanism for portable builds. ``GCC.enable_cpp11`` or
``MSVCPP.enable_cpp11`` are achieved by different means, but the Zef target will
call ``CPP_Compiler.enable_cpp11`` and it should do the right thing.

In order to achieve modularity, you can nest features as well. For example, if
the feature provider for a C compiler based on GCC doesn't implement an option
for enabling SSE3 intrinsics, you can code that provider yourself, place it in
``zef/providers`` inside the source tree and register it as
``zef.cc.enable_sse3``. Everything should work fine.

Every provider is asked by Zef if it needs access to some other features (so
this structure is also a DAG) and if it can implement itself on the current
platform. A GCC provider may want to bail out if GCC is not found on the system.
The providers also have access to specific options, so you can tell the GCC
provider to use a different GCC (perhaps for cross-compiling) or include your
own CFLAGS in each invocation.

A *provider conflict* arises when there are multiple different providers that
provide a feature required by the project. All provider conflicts must be 
resolved before the project is built, obviously. It is perfectly reasonable and
normal that provider conflicts come about, for example, if you have both GCC and
Clang on a system, so both GCC and Clang providers provide a C compiler
interface, which one should be used? In this case, the user is tasked with
picking the right provider. This allows you not to worry about adding options to
your project that obstruct the goals; no more CC variables or path prefixes. If
a provider conflict arises, you will be prompted to pick a certain provider or
even supply your own, on-the-fly. This achieves flexibility.

## Options

A project will define several options which control how it is being built.
Typical options are inclusions and exclusions of features, configuration of
debug levels, building a shared vs. a static library, etc. For each option, a
short description should be included, alongside allowed values (or a range of
values) and a default one, which will be used if the option is not provided,
making it non-mandatory. (If a default is lacking, the option is assumed to be
mandatory.)

## Targets

A *target* in Zef is simply an entity in the build process that can be created
out of other targets or physical files. An object file, generated from a C file,
is a target. A variable containing the list of all source files is also a
target. A build process is just a collection of targets, alongside dependencies
for each one, and some Lua code for each.

More precisely, a target is *always* a Lua function. For simple variables, a
target is just a static function which always returns the same value. For
variables which depend on other variables, a target is a function which
constructs a value based on these other variables and returns this one. We can
also define a target describing how to get to a certain file, or a target which
is a function that takes some arguments and returns some value. This should
become clear in a moment.

A target can depend on another target, a particular Zef feature being
implemented, a project option, a file in the source or build tree, a file whose
filename is the result of running a particular target function, or a list of
those. If a target T depends on a set D of dependencies, Zef assumes that as
long as none of the items in D change their values or side-effects, T will also
never change its value or side-effects.

# Files read by Zef

## Zeffile

In the project root, two files are required by Zef. The first one is a rather
easily human-readable YAML file called ``Zeffile``. ``Zeffile`` describes the
project, defines its name, options, version, etc. It is intended as a quick
reference for documentation of various options, much like ./configure --help.

Here is a sample ``Zeffile``. It describes a simple project with some simple
options. I don't feel like documenting the file format in detail; it is YAML and
it looks like below.

```yaml
project:
    name: Hello
    description: |
        Says hello to the people who run it. It is indeed
        a good program; I have spent many a countless 
        hours perfecting it.
    website: https://github.com/failwhale/hello
    version: 0.1.0
    options:
        - name: say_to_person
          allowed:
            - yes
            - no
          default: yes
          description: |
              Whether or not to support greeting a certain
              person by name or just say hello to the world.
              
        - name: debug_level
          allowed:
              - debug
              - release_with_debug_info
              - release
          default: debug
          description: |
              Which debug level to build with.

        - name: build_dir
          allowed: path
          default: ""
          description: |
              The path, absolute or relative to the project root,
              where the resulting files should be placed.

```

## Zefrules

A ``Zefrules`` file is a file which describes the build targets, their
dependencies and their code. Most of the file is really Lua, wrapped in a syntax
that eliminates much boilerplate and kind of resembles the syntax of traditional
Makefiles. Everything in a ``Zefrules`` file can be expressed directly in Lua,
by calling ``zef.*`` functions, but writing it this way aids clarity and
succinctness.

A demo ``Zefrules`` file I use as a testbed is reproduced below. I will also
attempt to write down some conventions on the syntax. It goes without saying
that this is unstable as hell and subject to very frequent change.

(I am not sure if Lua code is correct, that is completely beside the point.)

```
obj_dir_rel = "obj"
bin_dir_rel = "bin"
program_name = "hello"
src_dir = "src"

obj_dir = opts.build_dir .. obj_dir_rel
bin_dir = opts.build_dir .. bin_dir_rel
binary_filename = opts.build_dir .. program_name .. zef.cc.executable_extension()

src_files:
    zef.fs.glob(obj_dir .. "/*.c")

src_files: src/*.c opts.say_to_person
    files = zef.fs.glob(obj_dir .. "/*.c")
    if options.say_to_person then
        files["src/hello_world.c"] = nil
    else
        files["src/hello_person.c"] = nil

    return files



```
```
obj_dir_rel = "obj"
bin_dir_rel = "bin"
program_name = "hello"
src_dir = "src"

-- *****************************************

obj_dir: obj_dir_rel opts.build_dir {
    return hello.opts.build_dir .. hello.obj_dir_rel
}

bin_dir: bin_dir_rel opts.build_dir {
    return hello.opts.build_dir .. hello.bin_dir_rel
}

binary_filename: program_name opts.build_dir {
    return hello.opts.build_dir .. hello.program_name .. zef.cc.executable_extension()
}

c_compiler: zef.cc zef.cc.{link_only,compile_only,optimize,debug_symbols} {}

src_files: src/*.c opts.say_to_person {
    files = zef.fs.glob(obj_dir .. "/*.c")
    if options.say_to_person then
        files["src/hello_world.c"] = nil
    else
        files["src/hello_person.c"] = nil
    end

    return files
}

src_to_obj(src): {
    return zef.util.path_subst(
        src_dir . '/%.c',
        obj_dir . '/%.o')
}

obj_files: obj_dir src_files {
    return zef.map(hello.src_to_obj, hello.src_files)
}

compile_c(src, obj): c_compiler opts.debug_level {
    local optimization_level = {
        debug: 0,
        release_with_debug_info: 2,
        release: 2
    }

    local cc = zef.cc()
                .add_file(src)
                .compile_only()
                .optimize(optimization_level[hello.opts.debug_level])
                .output_to(obj)

    if hello.opts.debug_level == "debug" then
        cc.debug_symbols()
    end

    return cc.run()
}

link_binary(obj_files, binary): c_compiler {
    return zef.cc()
             .add_files(obj_files)
             .link_only()
             .output_to(binary)
             .run()
}

exposed $@binary_filename: $@obj_files link_binary {
    return hello.link_binary(hello.obj_files, hello.binary_filename)
}

exposed all: $@binary_filename {}
exposed clean: bin_dir obj_dir {
    return zef.fs.remove(zef.fs.glob(hello.bin_dir . '/*', hello.obj_dir . '/*'))
}

!src_file_rules: src_files compile_c {
    for src_file in pairs(hello.src_files)
        local obj_file = hello.src_to_obj(src_file)
        zef.add_target(
            hello,
            "$" .. obj_file,
            "$" .. src_file,
            function() 
                return hello.compile_c(src_file, obj_file)
            end)
    end
}
```

As you can see, targets are described as:

```
target_name [ ( argument* ) ] [ : dependency* ] {
    lua_code
}
```

``lua_code`` is the Lua code that the target consists of. It is ran inside a
function; the return value of that function is the return value of the target.

A target name may be prefixed with ``!`` which means it is a meta-target, which
means its job is to add other targets to  the build. This signals that they need
to be treated specially.

A target or dependency name may be prefixed with ``$``. This means that the
dependency or target name refers to a physical file in the source tree. This is
to avoid name clashes between named targets and files; make has ``.PHONY`` for
this.

A target or dependency name may be prefixed with ``@``, which means that the
name following it will be evaluated, and the output should be spliced into the
code itself. Let me clarify:

```
my_file_list: opts.some_file {
    return { "file1.c", "file2.c", "file3.c", project.opts.some_file }
)

my_target: my_file_list {
    ...
}
```

In this case, ``my_target`` will be re-run if the value of ``my_file_list``
changes; the return value of ``my_file_list`` will change if ``opts.some_file``
changes, for instance.

If ``my_target`` was, however, defined like this:

```
my_target: $@my_file_list {
    ...
}
```

Then it'll be rerun not only when the value of ``my_file_list`` changes, but
when ``file1.c``, ``file2.c``, ``file3.c`` or the filename described by
``project.opts.some_file`` changes. (Recall that ``$`` treats the value as
files, as opposed to target names.)

``exposed`` in front of a target means that this target is accessible to the
user building this project using Zef, by default, all targets are implicitly
internal to the Lua code in the project. This avoids cluttering the namespace
with pointless targets; if for some reason you *need* to build just a single
object file or some other internal target, this is a sign that the build system
is broken and needs fixing.

If the argument list is omitted, the target is assumed to take 0 arguments. If
the dependency list is omitted, the target output and side-effects are assumed
to never change. A special shorthand is this:

```
some_target = some_constant_expression
```

This is akin to writing

```
some_target: {
    return some_constant_expression
}
```

but is easier to write and is often useful to define some global variables.

Zef core functions and features reside under the ``zef`` table in Lua, targets
reside in the ``project_name`` table and user-configured options reside in
``project_name.opts``. In Lua code, the fully qualified names have to be used to
avoid name clashes, but inside ``Zefrules`` the ``project_name.`` part can be
omitted for succinctness.

You can see calls to ``zef.cc``, ``zef.fs.*`` or ``zef.add_target`` here, these
are just placeholders and the real design of these features and options will be
decided later, and probably in a separate document.

## zef/\*.zef and zef/\*.lua

Finally, files with the extension .lua within the `zef` subdirectory are all ran
to determine features and feature providers, prior to running any rules. When
all of these are parsed, Zef asks providers to register themselves if they can,
taking care to satisfy the dependency graph. Files with the extension .zef
within this directory can be included from the ``Zefrules`` file, it should be a
good practice to split build functionality between logically seperated .zef
files and include them from ``Zefrules``, especially for bigger projects.


