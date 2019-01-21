
# General Rules of Coding

This file describes the general rules of coding in the Kernal repo, including file formatting, naming convention, 
variable declaration rules, etc. Coding rules that are specific to individual modules and module documentation is 
contained in separate files.

## Module Assembly and Linking Process

The kernal consists of separate modules, each of which has its own assembly source file. Modules are concatenated
using ``cat`` utility before they are translated by the assembler, to provide global visibility of symbols. As a result, 
there is no linking phase. The combined file is named ``_loader_modules.tmp`` under ``bootsect`` directory. 