# Project README

## Prerequisites

To build and run this project, you'll need a Linux Ubuntu system with the following packages installed:

```sh
sudo apt-get install nasm gcc gcc-multilib g++-multilib libc6-dev-i386
```

## Compilation

To compile source code for the tasks 1-13 and 15 use:

```sh
nasm -f elf32 -o main.o main.asm
```

To compile and link source code for the task 14 use:

```sh
gcc -m32 -o main main.c
```

## Linking

To link binaries for the tasks 1-2, 10 use:

```sh
ld main.o -o main -m elf_i386
```

To link binaries for the tasks 3-9, 11-13, 15 use:

```sh
gcc -m32 -o main main.o
```
