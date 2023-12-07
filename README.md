# dev-environment

Dev Environment for developing with NeoVim. From inside the container itself.

- [Overview](#overview)
- [Showcase](#showcase)
- [Goals](#goals)
- [Current Stack and Tools](#current-stack-and-tools)
  - [Main Container](#main-container)
  - [Secondary Container (QMK)](#secondary-container-qmk)
  - [Windows and Linux Scripts](#windows-and-linux-scripts)

## Overview

> Para a versão em português vá para: [LEIAME.md](LEIAME.md)

This is a personal project to keep my main driver tools for development both for professional use and development-oriented fun projects (usually on a different container).

I do intend to reduce the size of both containers eventually, but for the time being, keep in mind they're considerably huge (specially the QMK one).

## Showcase

Project switching with tmux + fzf and fuzzy finding files inside the container:

![alt text](https://raw.githubusercontent.com/thomazmoura/image-samples/master/dev-environment/tmux_workflow.gif "Gif showing some features of the dev-environment container")

## Goals

My main intentions with this repo are:

  * Keep my main tools versioned and easily accessible, so I can easily download them anywhere;
  * Reduce the need of locally installing (or running) things as admin/root (the idea is that any root related settings will be done during build and the containers will run as non-privileged users);
  * Be a central reference to anyone who would like to check a particular tool or setting I use (basically a dotfile repo that you can run);
  * Have a working pipeline where I can update my settings and have them reproduced anywhere I might use them (possibly with automated tests like Software Composition Analysis);

## Current Stack and Tools

### Main Container

The container I use for most professional work.

* **Docker** - The main reason this repo exists is to try out the idea of keeping most of my development stack on a container (and develop from inside the container), so I use Docker for that.
* **NeoVim** - NeoVim is my main tool for development so it was my choice for editor/IDE-like-beast. I also native LTS packages and many plugins to achieve the usability I need.
* **TMUX** - I use it mostly to have a dedicated pane for terminal and for quick switching between projects.
* **PowerShell** - Call me a heretic, but I'm both a Linux and a PowerShell lover, so yep, I use mostly PowerShell as my main shell and this repo reflects that. Should be easy to change that on the DockerFile if so you want.
* **DotNet** - Call me a heretic again, but I just love coding C# on NeoVim on a tmux pane on Linux inside a container. Such an underrated experience... So anyway, the main container should have at least the supported LTS versions of .NET installed.
* **Angular** - I use mostly Angular for FrontEnd work (I'm a Full Stack developer), so there a few plugins focused on it.
* **Azure CLI** - I have a few scripts to make my life easier with Azure CLI with the Azure DevOps module, so I needed to add it here so I can still use them. I do intend to replace them with calls to the API or something like the VSTeam PowerShell module, because the az cli is huge.

### Secondary Container (QMK)

I've decided to create this sub-container (which uses the Main Container as base) to be able to add the requirements for building [QMK](https://github.com/qmk/qmk_firmware) (which is a mechanical keyboard open source firmware) and Rust without having to increase too much the Main Container size (QMK has a lot of dependencies).

* **C/C++** - Needed to build QMK. I use C only for customizing QMK layouts and features, so its support is not as great as other languages here.
* **Rust** - Since I had to make a second container to put QMK requirements, might as well put Rust dependencies too so I can use it as a study container.

### Windows and Linux Scripts

I mostly do my development inside the container, but there are situations on which it's more productive to resort to less "isolated solutions", like VS Code running on Windows or WSL2 (ideally, both). So I've added some scripts so I can more easily setup a new machine to use some of the same configuration I use on the docker containers on Windows Tools (like setting up NeoVim on Windows so I can use it with the VSCode-Neovim).
