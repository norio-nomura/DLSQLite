# DLSQLite
[![MIT License](http://img.shields.io/badge/license-MIT-blue.svg?style=flat)](LICENSE)
[![CI Status](http://img.shields.io/travis/norio-nomura/DLSQLite.svg?style=flat)](https://travis-ci.org/norio-nomura/DLSQLite)

`DLSQLite` is a [SQLite](http://www.sqlite.org) wrapper written in Swift 3.  
`DLSQLite` can be used in Playground without having to build the framework.

## Requirements

* Swift 3.0.2 or later
* SQLite

### SQLite Installation

#### macOS
Pre-installed `libsqlite3.dylib` can be used by `DLSQLite`.


#### Linux
```
$ sudo apt-get install libsqlite3-dev
```

## Setup

### Playground
Copy [DLSQLite.swift](https://raw.githubusercontent.com/norio-nomura/DLSQLite/master/Sources/DLSQLite.swift) into `Sources` folder in your Playground.

### Swift REPL (Swift 3.1)
```
$ TOOLCHAINS=swift PRODUCE_DYLIB=1 swift build
$ TOOLCHAINS=swift swift -I .build/debug -L .build/debug -lDLSQLite
Welcome to Apple Swift version 3.1-dev (LLVM a7c680da51, Clang df9f12fda6, Swift bafde97c26). Type :help for assistance.
  1> import Foundation # on Linux
  2> import DLSQLite
  3> SQLite.libVersion
$R0: String = "3.14.0"
```

## Author

Norio Nomura

## License

DLSQLite is available under the MIT license. See the LICENSE file for more info.
