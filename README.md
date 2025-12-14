# Dev Container Generator

A Bash script to **dynamically generate Docker/Podman development containers** based on predefined **profiles** and **categories**, with optional **Zsh setup** and a **rootless developer user**.

---

## **Features**

* Supports **Alpine** and **Debian** base images.
* Predefined profiles for common development stacks:

  * `WebDev`, `Embedded`, `DataScience`, `RE`, `FullStack`
* Flexible categories:

  * `C`, `Rust`, `Python`, `Node`, `Editors`, `Network`, `Debugging/RE`, `Database`
* Optional:

  * Zsh + Oh My Zsh plugins (`autosuggestions`, `syntax-highlighting`)
  * Rootless developer user with configurable UID
  * Custom working directory
* Supports **dry-run** (print Dockerfile only) and **build & run**.

---

## **Requirements**

* **Docker** or **Podman** installed
* Bash 4+
* Internet connection for package installation and Oh My Zsh

---

## **Installation**

Clone the repository from GitHub:

```bash
git clone https://github.com/rhjddjdbc/dcg.git
cd dcg
```

Make the script executable:

```bash
chmod +x dcg.sh
```

The script is now ready to use:

```bash
./dcg.sh --help
```

---

## **Usage**

### **Syntax**

```bash
./dcg.sh [options]
```

### **Options**

| Option                  | Description                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------------- |
| `--base <image>`        | Base image (`alpine:3.18`, `debian:12`, `debian:bookworm`). Default: `alpine:3.18`           |
| `--profile <profile>`   | Predefined profiles: `WebDev`, `Embedded`, `DataScience`, `RE`, `FullStack`. Can be repeated |
| `--categories "<list>"` | Additional categories, e.g., `"C Python Node Database"`                                      |
| `--user <name>`         | Developer username (default: `devuser`)                                                      |
| `--uid <uid>`           | UID of the user (default: `1000`)                                                            |
| `--workdir <path>`      | Working directory in container (default: `/workspace`)                                       |
| `--zsh`                 | Install Zsh + Oh My Zsh plugins                                                              |
| `--dry-run`             | Print Dockerfile content only                                                                |
| `--build-run`           | Build the image and start the container                                                      |
| `-h, --help`            | Show help                                                                                    |

---

### **Examples**

#### 1. Print Dockerfile (dry-run)

```bash
./dcg.sh --profile WebDev --zsh --dry-run
```

#### 2. Generate Dockerfile

```bash
./dcg.sh --profile FullStack --categories "C Python" --user devuser --uid 1000
```

#### 3. Build image and run container

```bash
./dcg.sh --profile DataScience --build-run
```

---

## **Rootless Dev Container**

* A **non-root user** is created (`--user` / `--uid`).
* No `sudo` is required – fully **rootless**.
* Zsh plugins are loaded automatically on container start.

---

## **Profiles & Categories**

### **Profiles**

| Profile     | Categories                                                      |
| ----------- | --------------------------------------------------------------- |
| WebDev      | Node, Python, Editors, Network, Database                        |
| Embedded    | C, Rust, Editors, Network, Debugging/RE                         |
| DataScience | Python, Editors, Database, git                                  |
| RE          | Debugging/RE, C, Editors, Network                               |
| FullStack   | Node, Python, Editors, Database, Network, C, Rust, Debugging/RE |

### **Categories & Tools**

| Category     | Tools                                                                                 |
| ------------ | ------------------------------------------------------------------------------------- |
| C            | gcc, make, clang, build-base/build-essential, gdb, strace, ltrace, binutils, valgrind |
| Rust         | rust, cargo, rustfmt, clippy, rust-analyzer                                           |
| Python       | python3, pip, ipython, jupyter, numpy, pandas, matplotlib                             |
| Node         | nodejs, npm, yarn                                                                     |
| Editors      | nano, neovim                                                                          |
| Network      | curl, wget, netcat, tcpdump, nmap, git, ca-certificates                               |
| Debugging/RE | gdb, strace, ltrace, radare2, file, readelf, lsof, objdump, valgrind                  |
| Database     | sqlite, postgresql-client, redis-tools                                                |

---

## **Tips**

* **Switch base image** carefully: package names differ (`apk` vs `apt-get`).
* **Zsh plugins** are installed automatically; no additional configuration needed.
* **Rootless security**: all files belong to the developer user.

---

## **License**

MIT – free to use and modify.
