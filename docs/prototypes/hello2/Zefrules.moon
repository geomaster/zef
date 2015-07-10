-- A metatarget. It does not generate new targets 
-- and does not result in an explicit file being built. 
-- In this case, it returns a list of source files 
-- (without the '.c'). Targets can, aside from having
-- side effects, return a value, which can be used from
-- another target. Note that this is actually a chain
-- of function calls looking like add(meta(target(...))),
-- where target() builds a target object, meta() modifies
-- it to register as a metatarget, and add() adds it
-- to the DAG.
add meta target 'sources', -> { 'main', 'module1', 'module2' }
        
-- This target is not used, it is here to illustrate
-- how a glob may be performed to find all files
-- instead of explicitly listing their names. In this
-- case, Zef will record the directory within which
-- the globbing takes place as a dependency itself, so
-- whenever the contents change, this metatarget will
-- be rebuilt. When a metatarget which generates other
-- targets is rebuilt, the old targets generated by it
-- are diffed with the new ones. If there are some
-- matches between the new and old targets (i.e. the 
-- names and the rules match), these will not be marked
-- as dirty and will be left untouched.
add meta target 'source_files_glob', -> fs.glob('src/*.c')

-- Another metatarget. Metatargets are allowed read-only
-- access to other targets and to the filesystem, but
-- they are not allowed to change anything -- their
-- only role is to define other targets. As such, 
-- they have precedence; all metatargets will be run
-- before any phony or file target is run. Because
-- they are the only type of target that can spawn 
-- others, we can assume that after all metatargets
-- were run, Zef knows about all of the files that 
-- can be built. The previous metatarget did not 
-- define any new targets and could have been a phony
-- one, however since this metatarget depends on it,
-- and metatargets must be built before all other 
-- targets, it follows that it must be a metatarget
-- for the dependency to be satisfied.
--
-- The `T` object inside the target rules is a 
-- shorthand for `targets`, which can invoke and 
-- retrieve the return value of an arbitrary target
-- by its name. Upon accessing another target, it 
-- becomes an implicit dependency of the current one.
-- In this case, if `sources` changes, it triggers
-- a rebuild of this metatarget. A `!` is used in
-- MoonScript to call a function with no arguments 
-- which is required in this case to execute the
-- target itself.
--
-- The `O` object inside the target rules is a 
-- shorthand for `options`. It can access options 
-- defined by the user in the configuration file.
-- Again, the option is recorded as a dependency 
-- for this target and anytime its value changes, it
-- will trigger a rebuild of this metatarget and/or
-- the targets generated by it.
--
-- `F` means `features`. It's a repository of 
-- 'features' currently available to this build 
-- script. In this case, we create a new `cc` feature,
-- which is a C compiler, and tell it what its inputs
-- and outputs are.
--
-- In the end, using the implicit return feature of
-- MoonScript, the metatarget returns the list of
-- object files, making it easy to include in the
-- next one.
--
-- `file` is a modifier available to scripts which 
-- wraps a string filename in a special 'datatype'
-- which denotes it is a file. When applied to a
-- target, though, it modifies it to be a file
-- target, which explains why we can do `add file
-- target`.
--
-- Also notice how the target definition inside the
-- rules body is the same as it would look like 
-- outside.
add meta target 'objfiles', -> 
    for x in *T.sources!
        src = "src/#{x}.c"
        obj = "#{O.build_dir}obj/#{x}.o"

        add file target obj, ->
            with F.cc!
                \input file src
                \output file obj
                \optimize O.optimization_level
                \run!

        obj

-- Another metatarget. In this case, both a second and
-- a third argument is given to `target`. This is a 
-- shorthand which takes the file(s) that the second
-- argument generates, and adds a target for each one of
-- them with the third argument as the body. Inside the
-- body, we access the return value of the `objfiles` 
-- target (adding it as an implicit dependency) and use
-- @output, where `@` is an alias for `self.`, which 
-- acceses the current target. In this case, `@output` (or 
-- `self.output`) returns the file used as the output from
-- this rule.
add meta target 'executable', -> file "#{O.build_dir}bin/hello", ->
    with F.cc!
        \input T.objfiles!
        \output @output
        \run!
        
-- A phony target. Its build triggers the build of the 
-- target generated by the `executable` metatarget. The
-- `targets` property of a metatarget returns all targets
-- built by it. Note that although the metatarget was
-- not explicitly executed (using a `!`), it is 
-- nevertheless recorded as a dependency.  If the `objfiles`
-- target didn't return a list of objects, we could have
-- just used \input(T.objfiles.targets) in the `executable`
-- target.

-- `visible` is a modifier used to make the target 
-- 'visible' when the user asks Zef to list all targets 
-- (this is for stylistic reasons, as 'visible' targets 
-- could be the ones performing some common tasks such as 
-- building everything, only some components, testing
-- etc.)
add visible target 'all', ->
    T.executable\targets!
   
