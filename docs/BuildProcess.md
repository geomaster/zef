# How Zef builds stuff

(Note that this document is not accurate, it's just a roadmap)
On running `zef build` the process proceeds as follows:

- First, the cache is consulted to see if we have any info on the project

- Then, the Zeffile is parsed and we can see if the data therein corresponds to
  the one in the cache. If there is no cache or crucial data is changed, we may
  need to mark some targets or meta-targets as dirty
    - If the Zeffile has not been changed since we cached its contents,
      obviously there is no need to reparse it

- After this, the providers within zef/providers are ran and they get
  registered. We may skip this if we detect no changes to the directory
  structure or files in zef/providers and we have the info in the cache

- The Zefrules file is parsed
    - Again, if the Zefrules file has not been changed since its contents have
      been cached, no need to parse it again. Just use the rule data from the
      cache.

- All meta-targets are promptly expanded; if we have the old DAG of meta-targets
  in the cache, we can rebuild only those whose dependencies have changed, if
  any
  
- The default target is located and we can figure out how to build it from its
  dependencies. If, during the build, a target accesses other dependencies than
  the ones we know of, we will recursively depth-first build them and add them
  to the new DAG

- The old and new DAG are compared. If they are not equal, we may need to clean
  up some nodes on the filesystem

- The old DAG is then changed so that newly discovered dependencies and
  dependencies that no longer exist are all reflected in the cache.

