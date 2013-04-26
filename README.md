FringeData
==========

An easy-to-use replacement for CoreData

CoreData is a pretty cool framework. I've had many uses for it and it's generally served my needs well.
However, a while back I was working on a heavily-threaded application where the objects needed to
be modified in a background processing thread as well as the UI thread. To do this in CoreData and not
have it eventually throw an exception at you requires so much locking that your app will become unusably slow.
And thus FringeData was born. It was designed from the start to strike a balance between memory usage, speed,
and thread-safety. You can safely read and write to a FringeDataObject from multiple threads and never have
to worry about locking (it's handled for you). Also, since it uses JSON formatted files for its backing store
it's trivial to add or remove properties from your FringeDataObject derived objects.

Advantages
==========
* Thread safe reads and writes
* FringeDataObject mimics NSManagedObject, so you can continue to use @dynamic properties
* Only holds changed and recently accessed objects in memory in order to maintain a low footprint
* Has simple begin/commit/rollback transactional ability
* JSON backed for human-readable data files and trivialy property addition
* FringeObjectStore(s) are reused, so there is never more than one instance representing a given backing store

Disadvantages
=============
* Indexing is file-system based and is therefore somewhat limited until I come up with something better

Requirements
============
* ARC - Sorry, weak references are far too useful to make porting to non-ARC worth the effort
* SBJSON - It's in the repo as a git submodule, just run "git submodule update --init"

How To Use
==========
Comming soon(ish)
