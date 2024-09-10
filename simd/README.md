# Project README

## Prerequisites

To build and run this project, you'll need a Linux Ubuntu system with the following packages installed:

```sh
sudo apt-get install nasm gcc gcc-multilib g++-multilib libc6-dev-i386
```

## \*.cpp files

To compile and link cpp files use:

```sh
g++ -march=native -o main main.cpp
```

## \*.asm files

To compile use:

```sh
nasm -f elf32 -o main.o main.asm
```

To link use:

```sh
gcc -m32 -o main main.o -nostartfiles
```
