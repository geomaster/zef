# Note on short-term planned features

* Make Zef able to scan the Zeffile in the current directory and put the results
  into the .Zefcache SQLite database.

* Run the provider Lua files in zef/providers and provide a Lua interface for
  them to register themselves.

* Parse the Zefrules file and be able to keep its structure in memory and in the
  .Zefcache.

* Build the first DAG linking meta-targets to their dependencies.

* Be able to expand the meta-targets to real ones.

* Build a new DAG showing the structure of the project and be able to invoke
  different ones.
